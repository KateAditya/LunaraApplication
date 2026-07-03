import User, { UserRole } from './User';
import Venue from './Venue';
import Booking from './Booking';
import GroupBooking from './GroupBooking';
import Payment from './Payment';
import BookingTablePackage from './BookingTablePackage';
import BookingMember from './BookingMember';
import Plan from './Plan';
import PlanJoinRequest from './PlanJoinRequest';
import Conversation from './Conversation';
import Message from './Message';
import PasswordResetToken from './PasswordResetToken';
import EmailVerification from './EmailVerification';
import OTPVerification from './OTPVerification';
import UserProfile from './UserProfile';
import UserPhoto from './UserPhoto';
import UserInterest from './UserInterest';
import UserPreference from './UserPreference';
import UserMatch from './UserMatch';
import SocialConnection from './SocialConnection';
import VenueImage from './VenueImage';
import VenueComplianceLog from './VenueComplianceLog';
import HelpArticle from './HelpArticle';
import CommunityGuideline from './CommunityGuideline';
import LegalDocument from './LegalDocument';
import PartyPlan from './PartyPlan';
import Ad from './Ad';
import GroupParty from './GroupParty';
import StrangersMeetRequest from './StrangersMeetRequest';
import PartyPlanRequest from './PartyPlanRequest';
import UserPenalty from './UserPenalty';
import City from './City';

// ============================================================================
// User Associations
// ============================================================================

// User -> Venues (owner)
User.hasMany(Venue, {
    foreignKey: 'ownerId',
    as: 'venues',
});

// User -> Bookings
User.hasMany(Booking, {
    foreignKey: 'userId',
    as: 'bookings',
});

// User -> Payments
User.hasMany(Payment, {
    foreignKey: 'userId',
    as: 'payments',
});

// User -> Group Bookings (organizer)
User.hasMany(GroupBooking, {
    foreignKey: 'organizerId',
    as: 'organizedGroupBookings',
});

// User -> Profile (1:1)
User.hasOne(UserProfile, {
    foreignKey: 'userId',
    as: 'profile',
    onDelete: 'CASCADE',
});

// User -> Photos
User.hasMany(UserPhoto, {
    foreignKey: 'userId',
    as: 'photos',
});

// User -> Interests
User.hasMany(UserInterest, {
    foreignKey: 'userId',
    as: 'interests',
});

// User -> Preferences (1:1)
User.hasOne(UserPreference, {
    foreignKey: 'userId',
    as: 'preferences',
    onDelete: 'CASCADE',
});

// User -> Password Reset Tokens
User.hasMany(PasswordResetToken, {
    foreignKey: 'userId',
    as: 'passwordResetTokens',
});

// User -> Email Verifications
User.hasMany(EmailVerification, {
    foreignKey: 'userId',
    as: 'emailVerifications',
});

// ============================================================================
// Venue Associations
// ============================================================================

Venue.belongsTo(User, {
    foreignKey: 'ownerId',
    as: 'owner',
});

Venue.hasMany(Booking, {
    foreignKey: 'venueId',
    as: 'bookings',
    onDelete: 'CASCADE',
});

Venue.hasMany(VenueImage, {
    foreignKey: 'venueId',
    as: 'images',
    onDelete: 'CASCADE',
});

// Venue -> Compliance Logs
Venue.hasMany(VenueComplianceLog, {
    foreignKey: 'venueId',
    as: 'complianceLogs',
    onDelete: 'CASCADE',
});

// Venue -> Ads
Venue.hasMany(Ad, {
    foreignKey: 'venueId',
    as: 'ads',
    onDelete: 'CASCADE',
});

Ad.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

VenueComplianceLog.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

// ============================================================================
// Booking Associations
// ============================================================================

Booking.belongsTo(User, {
    foreignKey: 'userId',
    as: 'customer',
});

Booking.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

Booking.hasOne(GroupBooking, {
    foreignKey: 'bookingId',
    as: 'groupBooking',
});

Booking.hasMany(Payment, {
    foreignKey: 'bookingId',
    as: 'payments',
});

// Booking -> TablePackages
Venue.hasMany(BookingTablePackage, {
    foreignKey: 'venueId',
    as: 'tablePackages',
    onDelete: 'CASCADE',
});
BookingTablePackage.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

// GroupBooking -> BookingMembers
GroupBooking.hasMany(BookingMember, {
    foreignKey: 'groupBookingId',
    as: 'members',
});
BookingMember.belongsTo(GroupBooking, {
    foreignKey: 'groupBookingId',
    as: 'groupBooking',
});

// ============================================================================
// Group Booking Associations
// ============================================================================

GroupBooking.belongsTo(Booking, {
    foreignKey: 'bookingId',
    as: 'booking',
});

GroupBooking.belongsTo(User, {
    foreignKey: 'organizerId',
    as: 'organizer',
});

// ============================================================================
// Payment Associations
// ============================================================================

Payment.belongsTo(Booking, {
    foreignKey: 'bookingId',
    as: 'booking',
});

Payment.belongsTo(User, {
    foreignKey: 'userId',
    as: 'payer',
});

// ============================================================================
// User Profile Associations
// ============================================================================

UserProfile.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// User Photo Associations
// ============================================================================

UserPhoto.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// User Interest Associations
// ============================================================================

UserInterest.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// User Preference Associations
// ============================================================================

UserPreference.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Password Reset Token Associations
// ============================================================================

PasswordResetToken.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Email Verification Associations
// ============================================================================

EmailVerification.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Social Connection Associations
// ============================================================================

SocialConnection.belongsTo(User, {
    foreignKey: 'requesterId',
    as: 'requester',
});

SocialConnection.belongsTo(User, {
    foreignKey: 'receiverId',
    as: 'receiver',
});

// ============================================================================
// User Match Associations
// ============================================================================

UserMatch.belongsTo(User, {
    foreignKey: 'user1Id',
    as: 'user1',
});

UserMatch.belongsTo(User, {
    foreignKey: 'user2Id',
    as: 'user2',
});

UserMatch.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'suggestedVenue',
    onDelete: 'SET NULL',
});

// ============================================================================
// Venue Image Associations
// ============================================================================

VenueImage.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

VenueImage.belongsTo(User, {
    foreignKey: 'uploadedBy',
    as: 'uploader',
});

// ============================================================================
// Plan Associations
// ============================================================================

User.hasMany(Plan, { foreignKey: 'userId', as: 'plans' });
Plan.belongsTo(User, { foreignKey: 'userId', as: 'host' });

Venue.hasMany(Plan, { foreignKey: 'venueId', as: 'plans', onDelete: 'CASCADE' });
Plan.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

// ============================================================================
// Party Plan Associations
// ============================================================================

User.hasMany(PartyPlan, { foreignKey: 'userId', as: 'partyPlans' });
PartyPlan.belongsTo(User, { foreignKey: 'userId', as: 'creator' });

Venue.hasMany(PartyPlan, { foreignKey: 'venueId', as: 'partyPlans', onDelete: 'CASCADE' });
PartyPlan.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

PartyPlan.hasMany(PartyPlanRequest, { foreignKey: 'planId', as: 'requests', onDelete: 'CASCADE' });
PartyPlanRequest.belongsTo(PartyPlan, { foreignKey: 'planId', as: 'plan' });

PartyPlanRequest.belongsTo(User, { foreignKey: 'requesterId', as: 'requester' });
User.hasMany(PartyPlanRequest, { foreignKey: 'requesterId', as: 'partyPlanRequests' });

User.hasMany(UserPenalty, { foreignKey: 'userId', as: 'penalties', onDelete: 'CASCADE' });
UserPenalty.belongsTo(User, { foreignKey: 'userId', as: 'user' });

// ============================================================================
// Group Party Associations
// ============================================================================

User.hasMany(GroupParty, { foreignKey: 'userId', as: 'groupParties' });
GroupParty.belongsTo(User, { foreignKey: 'userId', as: 'creator' });

Venue.hasMany(GroupParty, { foreignKey: 'venueId', as: 'groupParties', onDelete: 'CASCADE' });
GroupParty.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

// ============================================================================
// Strangers Meet Request Associations
// ============================================================================

User.hasMany(StrangersMeetRequest, { foreignKey: 'userId', as: 'strangersMeetRequests' });
StrangersMeetRequest.belongsTo(User, { foreignKey: 'userId', as: 'user' });

Venue.hasMany(StrangersMeetRequest, { foreignKey: 'venueId', as: 'strangersMeetRequests', onDelete: 'CASCADE' });
StrangersMeetRequest.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

Plan.hasMany(PlanJoinRequest, { foreignKey: 'planId', as: 'joinRequests' });
PlanJoinRequest.belongsTo(Plan, { foreignKey: 'planId', as: 'plan' });

PlanJoinRequest.belongsTo(User, { foreignKey: 'requesterId', as: 'requester' });
User.hasMany(PlanJoinRequest, { foreignKey: 'requesterId', as: 'planJoinRequests' });

// ============================================================================
// Chat Associations
// ============================================================================

User.hasMany(Conversation, { foreignKey: 'participantOne', as: 'conversationsAsOne' });
User.hasMany(Conversation, { foreignKey: 'participantTwo', as: 'conversationsAsTwo' });
Conversation.belongsTo(User, { foreignKey: 'participantOne', as: 'userOne' });
Conversation.belongsTo(User, { foreignKey: 'participantTwo', as: 'userTwo' });

Conversation.hasMany(Message, { foreignKey: 'conversationId', as: 'messages' });
Message.belongsTo(Conversation, { foreignKey: 'conversationId', as: 'conversation' });

Message.belongsTo(User, { foreignKey: 'senderId', as: 'sender' });
User.hasMany(Message, { foreignKey: 'senderId', as: 'sentMessages' });

// ============================================================================
// Exports
// ============================================================================

export {
    User,
    UserRole,
    Venue,
    Booking,
    GroupBooking,
    Payment,
    BookingTablePackage,
    BookingMember,
    Plan,
    PlanJoinRequest,
    Conversation,
    Message,
    PasswordResetToken,
    EmailVerification,
    OTPVerification,
    UserProfile,
    UserPhoto,
    UserInterest,
    UserPreference,
    UserMatch,
    SocialConnection,
    VenueImage,
    VenueComplianceLog,
    HelpArticle,
    CommunityGuideline,
    LegalDocument,
    PartyPlan,
    Ad,
    GroupParty,
    StrangersMeetRequest,
    PartyPlanRequest,
    UserPenalty,
    City,
};

// Export sync function
export const syncModels = async (options?: { force?: boolean; alter?: boolean }) => {
    try {
        // Sync in order of dependencies
        await User.sync(options);
        await Venue.sync(options);
        await Booking.sync(options);
        await GroupBooking.sync(options);
        await Payment.sync(options);
        await BookingTablePackage.sync(options);
        await BookingMember.sync(options);
        await Plan.sync(options);
        await PlanJoinRequest.sync(options);
        await Conversation.sync(options);
        await Message.sync(options);
        await PasswordResetToken.sync(options);
        await EmailVerification.sync(options);
        await OTPVerification.sync(options);
        await UserProfile.sync(options);
        await UserPhoto.sync(options);
        await UserInterest.sync(options);
        await UserPreference.sync(options);
        await UserMatch.sync(options);
        await SocialConnection.sync(options);
        await VenueImage.sync(options);
        await VenueComplianceLog.sync(options);
        await HelpArticle.sync(options);
        await CommunityGuideline.sync(options);
        await LegalDocument.sync(options);
        await PartyPlan.sync(options);
        await Ad.sync(options);
        await GroupParty.sync(options);
        await StrangersMeetRequest.sync(options);
        await PartyPlanRequest.sync(options);
        await UserPenalty.sync(options);
        await City.sync(options);

        console.log('✅ All models synchronized successfully');
    } catch (error) {
        console.error('❌ Error synchronizing models:', error);
        throw error;
    }
};

export default {
    User,
    Venue,
    Booking,
    GroupBooking,
    Payment,
    BookingTablePackage,
    BookingMember,
    Plan,
    PlanJoinRequest,
    Conversation,
    Message,
    PasswordResetToken,
    EmailVerification,
    OTPVerification,
    UserProfile,
    UserPhoto,
    UserInterest,
    UserPreference,
    UserMatch,
    SocialConnection,
    VenueImage,
    VenueComplianceLog,
    HelpArticle,
    CommunityGuideline,
    LegalDocument,
    PartyPlan,
    Ad,
    GroupParty,
    StrangersMeetRequest,
    PartyPlanRequest,
    UserPenalty,
    City,
    syncModels,
};
