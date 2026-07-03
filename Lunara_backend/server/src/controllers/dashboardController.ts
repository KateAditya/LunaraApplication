import { Request, Response } from 'express';

// Dummy data for Featured Venues (matches mobile app)
const featuredVenues = [
    {
        id: '1',
        name: 'OBSIDIAN LOUNGE',
        type: 'TECHNO • VIP',
        image: 'https://images.unsplash.com/photo-1574094939444-49ce857bc28e?auto=format&fit=crop&w=600&q=80',
        promoted: true
    },
    {
        id: '2',
        name: 'NEBULA CLUB',
        type: 'HOUSE • DANCE',
        image: 'https://images.unsplash.com/photo-1545128485-c400e7702796?auto=format&fit=crop&w=600&q=80',
        promoted: true
    }
];

// Dummy data for Party Tonight
const partyTonight = [
    {
        id: '1',
        title: 'Underground Techno Rave',
        location: 'Sector 7, The Vault',
        time: 'Tonight, 11:00 PM',
        attendees: 124,
        image: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=400&q=80'
    }
];

// Dummy data for Find Partner
const partyPartners = [
    {
        id: '1',
        name: 'Zane',
        vibe: 'Techno @ Obsidian',
        image: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80'
    },
    {
        id: '2',
        name: 'Lyra',
        vibe: 'Rooftop Chill',
        image: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=200&q=80'
    }
];

// Dummy data for Nearby Venues
const nearbyVenues = [
    {
        id: '1',
        name: 'Neon Bar',
        distance: '0.5 km away',
        image: 'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=300&q=80'
    },
    {
        id: '2',
        name: 'Sky Lounge',
        distance: '1.2 km away',
        image: 'https://images.unsplash.com/photo-1566737236500-c8ac43014a67?auto=format&fit=crop&w=300&q=80'
    }
];

export const getFeaturedVenues = async (_req: Request, res: Response) => {
    try {
        res.json({ success: true, count: 2, data: featuredVenues });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};

export const getPartyTonight = async (_req: Request, res: Response) => {
    try {
        res.json({ success: true, count: 1, data: partyTonight });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};

export const getPartyPartners = async (_req: Request, res: Response) => {
    try {
        res.json({ success: true, count: 2, data: partyPartners });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};

export const getNearbyVenues = async (_req: Request, res: Response) => {
    try {
        res.json({ success: true, count: 2, data: nearbyVenues });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};
