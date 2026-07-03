import sequelize from '../config/database';
import { User, UserProfile, UserPreference } from '../models';

export interface SetupProfileData {
    // Basic & Vibe Profile Data
    displayName?: string;
    bio?: string;
    gender?: string;
    city?: string;
    occupation?: string;
    education?: string;
    company?: string;

    // Privacy & Preferences Data
    smokingPreference?: string;
    drinkingHabit?: string; // Appears we might combine parsing if drinkingHabit exists
    musicPreference?: string[];
    drinkPreference?: string[];
    preferredGenders?: string[];
    minAgePreference?: number;
    maxAgePreference?: number;
    budgetRange?: string;
    showMeInMatching?: boolean;
    matchDistanceKm?: number;
}

export class UserService {
    /**
     * Handles the massive data payload from the 4-step mobile onboarding UX.
     * Uses a transaction to ensure if preferences fail, the profile isn't half-written.
     * 
     * @param userId UUID of the user
     * @param data SetupProfileData payload from the mobile frontend
     */
    public static async setupProfile(userId: string, data: SetupProfileData) {
        // Start a managed transaction wrapper
        return await sequelize.transaction(async (t) => {
            // 1. Verify User Exists
            const user = await User.findByPk(userId, { transaction: t });
            if (!user) {
                throw new Error('User not found');
            }

            // 2. Upsert UserProfile (Details, bio, gender, education, occupation)
            const profilePayload = {
                displayName: data.displayName,
                bio: data.bio,
                gender: data.gender,
                city: data.city,
                occupation: data.occupation,
                education: data.education,
                company: data.company
            };

            // Remove undefined fields so we don't overwrite existing db rows with nulls
            const cleanProfilePayload = Object.fromEntries(
                Object.entries(profilePayload).filter(([_, v]) => v !== undefined)
            );

            await UserProfile.upsert({
                userId,
                ...cleanProfilePayload
            }, { transaction: t });


            // 3. Upsert UserPreference (Genders, Ages, Music, Drinks, Smoking)
            const preferencePayload = {
                musicPreference: data.musicPreference,
                drinkPreference: data.drinkPreference,
                smokingPreference: data.smokingPreference,
                preferredGenders: data.preferredGenders,
                minAgePreference: data.minAgePreference,
                maxAgePreference: data.maxAgePreference,
                budgetRange: data.budgetRange,
                showMeInMatching: data.showMeInMatching,
                matchDistanceKm: data.matchDistanceKm,
            };

            const cleanPreferencePayload = Object.fromEntries(
                Object.entries(preferencePayload).filter(([_, v]) => v !== undefined)
            );

            // Fetch to ensure we don't overwrite defaults blindly
            let userPref = await UserPreference.findOne({ where: { userId }, transaction: t });

            if (userPref) {
                await userPref.update(cleanPreferencePayload, { transaction: t });
            } else {
                await UserPreference.create({ userId, ...cleanPreferencePayload }, { transaction: t });
            }

            // Mark User setup as truthy if certain thresholds met? Optional.
            // Returning the full refreshed data back.
            const fullProfile = await UserProfile.findOne({ where: { userId }, transaction: t });
            const fullPreferences = await UserPreference.findOne({ where: { userId }, transaction: t });

            return {
                profile: fullProfile,
                preferences: fullPreferences
            };
        });
    }
}
