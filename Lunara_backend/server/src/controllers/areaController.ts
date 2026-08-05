import { Request, Response } from 'express';
import Area from '../models/Area';
import Venue from '../models/Venue';
import { Op } from 'sequelize';

const DEFAULT_AREAS = [
    'Wakad',
    'Hinjewadi',
    'Baner',
    'Aundh',
    'Koregaon park',
    'Kalyani Nagar',
    'Camp',
    'Shivaji nagar',
    'Viman Nagar',
    'Balewadi',
    'Pune station',
    'Pune',
];

/**
 * Get all areas (combining seeded areas, dynamic Area model DB entries, and venue areas)
 */
export const getAreas = async (req: Request, res: Response): Promise<Response> => {
    try {
        // Fetch saved areas from Area table
        const dbAreas = await Area.findAll({
            where: { isActive: true },
            order: [['displayOrder', 'ASC'], ['name', 'ASC']],
        });

        const dbAreaNames = dbAreas.map(a => a.name);

        // Fetch distinct areas from existing venues
        const venueAreas = await Venue.findAll({
            attributes: ['area'],
            where: {
                area: {
                    [Op.and]: [
                        { [Op.ne]: null },
                        { [Op.ne]: '' }
                    ]
                }
            },
            group: ['area'],
            raw: true,
        }) as unknown as Array<{ area: string }>;

        const venueAreaNames = venueAreas.map(v => v.area).filter(Boolean);

        // Combine default areas, DB areas, and venue areas
        const allAreasSet = new Set<string>();

        // Add default areas first
        DEFAULT_AREAS.forEach(name => allAreasSet.add(name));
        // Add DB areas
        dbAreaNames.forEach(name => allAreasSet.add(name));
        // Add venue areas
        venueAreaNames.forEach(name => allAreasSet.add(name));

        const areasList = Array.from(allAreasSet);

        return res.status(200).json({
            success: true,
            data: areasList,
            details: dbAreas,
        });
    } catch (error: any) {
        console.error('Error fetching areas:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to fetch areas',
            error: error.message,
        });
    }
};

/**
 * Create a new area and save it to the DB
 */
export const createArea = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { name, city } = req.body;

        if (!name || typeof name !== 'string' || !name.trim()) {
            return res.status(400).json({
                success: false,
                message: 'Area name is required',
            });
        }

        const trimmedName = name.trim();

        // Check if area already exists (case-insensitive check)
        const [area, created] = await Area.findOrCreate({
            where: {
                name: {
                    [Op.iLike]: trimmedName,
                },
            },
            defaults: {
                name: trimmedName,
                city: city ? city.trim() : 'Pune',
                isActive: true,
                displayOrder: 0,
            },
        });

        return res.status(201).json({
            success: true,
            data: area,
            created,
            message: created ? 'Area created successfully' : 'Area already exists',
        });
    } catch (error: any) {
        console.error('Error creating area:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to create area',
            error: error.message,
        });
    }
};
