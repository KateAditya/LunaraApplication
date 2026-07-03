import type { User } from '../types/user';

export const DEMO_USERS_EXPANDED: User[] = [
    {
        id: '1',
        firstName: 'Priya',
        lastName: 'Sharma',
        email: 'priya.sharma@gmail.com',
        phone: '9876543210',
        role: 'customer',
        avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=200&h=200',
        isActive: true,
        isVerified: true,
        isPhoneVerified: true,
        isEmailVerified: true,
        createdAt: '2024-01-15T10:30:00Z',
        updatedAt: '2024-02-05T08:00:00Z',
        lastLoginAt: '2024-02-05T12:30:00Z',
        identity: {
            panNumber: 'ABCDE1234F',
            dob: '1995-08-22',
            gender: 'female',
            nationality: 'Indian'
        },
        social: {
            bio: 'Nightlife enthusiast, cocktail lover, and a fan of deep house. Looking for the best rooftop vibes in Mumbai!',
            interests: ['Techno', 'Cocktails', 'Rooftops', 'Live Music'],
            vibes: ['Energetic', 'Social', 'Luxury'],
            languages: ['English', 'Hindi', 'Marathi'],
            profilePhotos: [
                'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=600&h=800',
                'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?auto=format&fit=crop&q=80&w=600&h=800'
            ]
        },
        security: {
            mfaEnabled: true,
            lastPasswordChange: '2024-01-20T00:00:00Z',
            forcePasswordChange: false,
            loginHistory: [
                { timestamp: '2024-02-05T12:30:00Z', ip: '192.168.1.1', device: 'iPhone 15 Pro', location: 'Mumbai, India' },
                { timestamp: '2024-02-04T22:15:00Z', ip: '192.168.1.1', device: 'iPhone 15 Pro', location: 'Mumbai, India' }
            ]
        },
        history: {
            bookings: [
                { id: 'b1', venueName: 'Club Infinity', date: '2024-02-01T21:00:00Z', status: 'completed', amount: 5000 },
                { id: 'b2', venueName: 'Skybar', date: '2024-01-20T22:30:00Z', status: 'completed', amount: 3500 }
            ],
            payments: [
                { id: 'p1', amount: 5000, status: 'success', date: '2024-02-01T21:05:00Z', method: 'UPI' },
                { id: 'p2', amount: 3500, status: 'success', date: '2024-01-20T22:35:00Z', method: 'Credit Card' }
            ],
            reviews: [
                { id: 'r1', venueName: 'Club Infinity', rating: 5, comment: 'Amazing music and vibe!', date: '2024-02-02T10:00:00Z' }
            ]
        }
    },
    {
        id: '2',
        firstName: 'Rahul',
        lastName: 'Patel',
        email: 'rahul.patel@gmail.com',
        phone: '9876543211',
        role: 'customer',
        isActive: true,
        isVerified: true,
        isPhoneVerified: true,
        isEmailVerified: true,
        createdAt: '2024-01-20T12:00:00Z',
        updatedAt: '2024-02-01T21:00:00Z',
        lastLoginAt: '2024-02-05T09:00:00Z',
        identity: {
            panNumber: 'FGHIJ5678K',
            dob: '1992-05-12',
            gender: 'male',
            nationality: 'Indian'
        },
        social: {
            bio: 'Tech by day, techno by night. Always looking for new underground scenes and craft beers.',
            interests: ['Techno', 'Beer', 'Underground', 'Live Music'],
            vibes: ['Chill', 'Underground'],
            languages: ['English', 'Gujarati', 'Hindi'],
            profilePhotos: [
                'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&q=80&w=600&h=800'
            ]
        },
        security: {
            mfaEnabled: false,
            lastPasswordChange: '2024-01-20T12:00:00Z',
            forcePasswordChange: true,
            loginHistory: [
                { timestamp: '2024-02-05T09:00:00Z', ip: '192.168.1.5', device: 'MacBook Pro', location: 'Ahmedabad, India' }
            ]
        },
        history: {
            bookings: [],
            payments: [],
            reviews: []
        }
    },
    {
        id: '3',
        firstName: 'Ananya',
        lastName: 'Reddy',
        email: 'ananya.reddy@gmail.com',
        phone: '9876543212',
        role: 'venue_owner',
        isActive: true,
        isVerified: true,
        isPhoneVerified: true,
        isEmailVerified: true,
        createdAt: '2024-01-22T14:30:00Z',
        updatedAt: '2024-02-03T09:00:00Z',
        lastLoginAt: '2024-02-05T11:00:00Z',
        identity: {
            panNumber: 'KLMNO9012P',
            dob: '1988-11-30',
            gender: 'female',
            nationality: 'Indian'
        },
        social: {
            bio: 'Owner of Club Infinity. Passionate about creating the best nightlife experiences in the city.',
            interests: ['House', 'Fine Dining', 'Business'],
            vibes: ['Professional', 'Luxury'],
            languages: ['English', 'Telugu', 'Hindi'],
            profilePhotos: [
                'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=600&h=800'
            ]
        },
        security: {
            mfaEnabled: true,
            lastPasswordChange: '2024-01-22T14:30:00Z',
            forcePasswordChange: false,
            loginHistory: [
                { timestamp: '2024-02-05T11:00:00Z', ip: '192.168.0.10', device: 'Windows Desktop', location: 'Hyderabad, India' }
            ]
        },
        history: {
            bookings: [],
            payments: [],
            reviews: []
        }
    }
];
