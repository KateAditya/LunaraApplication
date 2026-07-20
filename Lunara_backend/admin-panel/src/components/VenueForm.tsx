import React, { useState, useEffect } from 'react';
import {
    BiX, BiSave, BiChevronLeft, BiChevronRight,
    BiInfoCircle, BiMap, BiPhone, BiTime, BiBriefcase, BiGridAlt,
    BiCheckCircle, BiImage, BiUpload, BiTrash, BiPlus, BiVideo
} from 'react-icons/bi';
import type { Venue, VenueCategory, VenueAmenities, VenueStatus } from '../types/venue';
import { AMENITY_CONFIG, CATEGORY_CONFIG } from '../types/venue';
import { toast } from 'react-hot-toast';
import { ImageCropModal } from './ImageCropModal';
import { fileToDataUrl, validateImageFile } from '../utils/cropUtils';
import { processImageFiles, processVideoFiles } from '../utils/mediaValidation';

interface VenueFormProps {
    venue?: Venue | null;
    onClose: () => void;
    onSave: (data: any) => void;
}

export interface VenueFormState {
    [key: string]: any;
    name: string;
    tagline: string;
    description: string;
    category: VenueCategory;
    tags: string;
    status: VenueStatus;
    isActive: boolean;
    isFeatured: boolean;
    isPremium: boolean;

    // Flattened location
    addressLine1: string;
    addressLine2: string;
    area: string;
    city: string;
    state: string;
    pincode: string;
    country: string;
    latitude: string;
    longitude: string;
    displayOrder: string;
    nearestLandmark: string;
    directions: string;

    // Flattened contact
    phone: string;
    mobile: string;
    whatsapp: string;
    email: string;
    website: string;
    instagram: string;
    facebook: string;
    cpName: string;
    cpDesignation: string;
    cpMobile: string;
    cpEmail: string;
    altCpName: string;
    altCpDesignation: string;
    altCpMobile: string;
    altCpEmail: string;

    // Flattened operations
    openingTime: string;
    closingTime: string;
    daysOpen: string[];
    closedDates: string;
    seatingCapacity: string;
    standingCapacity: string;
    coverChargeMale: string;
    coverChargeFemale: string;
    discountPercentage: string;
    tableBookingCharges: string;
    coupleEntryFee: string;
    ageLimit: string;
    dressCode: string;
    cuisineTypes: string[];
    musicTypes: string[];

    // Flattened business
    panNumber: string;
    gstNumber: string;
    fssaiLicense: string;
    liquorLicense: string;
    fireSafetyCert: string;
    tradeLicense: string;
    bankAccountNumber: string;
    bankIFSC: string;
    bankName: string;

    amenities: VenueAmenities;
    media: any;

    _coverFile?: File | null;
    _photoFiles?: File[];
    _videoFiles?: File[];
    _menuFiles?: File[];
    _foodMenuFiles?: File[];
    _barMenuFiles?: File[];
    _beverageMenuFiles?: File[];
    _partyPackagesFiles?: File[];
}

const getDefaultForm = (venue?: Venue | null): Record<string, any> => ({
    // Basic
    name: venue?.name || '',
    tagline: venue?.tagline || '',
    description: venue?.description || '',
    category: venue?.category || 'club' as VenueCategory,
    tags: venue?.tags?.join(', ') || '',
    status: venue?.status || 'pending',
    isActive: venue?.isActive ?? true,
    isFeatured: venue?.isFeatured ?? false,
    isPremium: venue?.isPremium ?? false,

    // Location
    addressLine1: venue?.location?.addressLine1 || '',
    addressLine2: venue?.location?.addressLine2 || '',
    area: venue?.location?.area || '',
    city: venue?.location?.city || '',
    state: venue?.location?.state || '',
    pincode: venue?.location?.pincode || '',
    country: venue?.location?.country || 'India',
    latitude: venue?.location?.latitude?.toString() || '',
    longitude: venue?.location?.longitude?.toString() || '',
    displayOrder: venue?.displayOrder?.toString() || '0',
    nearestLandmark: venue?.location?.nearestLandmark || '',
    directions: venue?.location?.directions || '',

    // Contact
    phone: venue?.contact?.phone || '',
    mobile: venue?.contact?.mobile || '',
    whatsapp: venue?.contact?.whatsapp || '',
    email: venue?.contact?.email || '',
    website: venue?.contact?.website || '',
    instagram: venue?.contact?.instagram || '',
    facebook: venue?.contact?.facebook || '',
    cpName: venue?.contactPerson?.name || '',
    cpDesignation: venue?.contactPerson?.designation || '',
    cpMobile: venue?.contactPerson?.mobile || '',
    cpEmail: venue?.contactPerson?.email || '',
    altCpName: venue?.altContactPerson?.name || '',
    altCpDesignation: venue?.altContactPerson?.designation || '',
    altCpMobile: venue?.altContactPerson?.mobile || '',
    altCpEmail: venue?.altContactPerson?.email || '',

    // Operations
    openingTime: venue?.operations?.openingTime || '19:00',
    closingTime: venue?.operations?.closingTime || '01:30',
    daysOpen: venue?.operations?.daysOpen || [...DAYS],
    closedDates: venue?.operations?.closedDates?.join(', ') || '',
    seatingCapacity: venue?.operations?.seatingCapacity?.toString() || '',
    standingCapacity: venue?.operations?.standingCapacity?.toString() || '',
    coverChargeMale: venue?.operations?.coverChargeMale?.toString() || '',
    coverChargeFemale: venue?.operations?.coverChargeFemale?.toString() || '',
    discountPercentage: venue?.operations?.discountPercentage?.toString() || '',
    tableBookingCharges: venue?.operations?.tableBookingCharges?.toString() || '',
    coupleEntryFee: venue?.operations?.coupleEntryFee?.toString() || '0',
    ageLimit: venue?.operations?.ageLimit?.toString() || '21',
    dressCode: venue?.operations?.dressCode || '',
    cuisineTypes: venue?.operations?.cuisineTypes || [],
    musicTypes: venue?.operations?.musicTypes || [],

    // Business
    panNumber: venue?.business?.panNumber || '',
    gstNumber: venue?.business?.gstNumber || '',
    fssaiLicense: venue?.business?.fssaiLicense || '',
    liquorLicense: venue?.business?.liquorLicense || '',
    fireSafetyCert: venue?.business?.fireSafetyCert || '',
    tradeLicense: venue?.business?.tradeLicense || '',
    bankAccountNumber: venue?.business?.bankAccountNumber || '',
    bankIFSC: venue?.business?.bankIFSC || '',
    bankName: venue?.business?.bankName || '',

    // Amenities
    amenities: venue?.amenities || {
        hasWifi: false, hasAC: false, hasParking: false, hasValetParking: false,
        hasSmokingZone: false, hasDanceFloor: false, hasOutdoorSeating: false,
        hasRooftop: false, hasPool: false, hasVIPSection: false, hasBottleService: false,
        hasLiveMusic: false, hasDJ: false, hasHappyHours: false, hasPrivateDining: false,
    } as VenueAmenities,

    // File references for upload (not persisted)
    _coverFile: null,
    _photoFiles: [],
    _videoFiles: [],
    _menuFiles: [],
    _foodMenuFiles: [],
    _barMenuFiles: [],
    _beverageMenuFiles: [],
    _partyPackagesFiles: [],

    // Media — include three menu buckets
    media: {
        coverImage: venue?.media?.coverImage || '',
        photos: venue?.media?.photos || [],
        videos: venue?.media?.videos || [],
        menus: venue?.media?.menus || [],
        foodMenus: venue?.media?.foodMenus || [],
        barMenus: venue?.media?.barMenus || [],
        beverageMenus: venue?.media?.beverageMenus || [],
        partyPackages: venue?.media?.partyPackages || [],
    } as any,

    // Legal — must be freshly accepted on every new submission
    termsAccepted: false,
});

/* ═════════ STYLES ═════════ */
const overlay: React.CSSProperties = { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1080, backdropFilter: 'blur(4px)' };
const panel: React.CSSProperties = { width: '100%', maxWidth: 780, maxHeight: '92vh', display: 'flex', flexDirection: 'column', borderRadius: 'var(--vz-radius-lg)', overflow: 'hidden', boxShadow: '0 8px 40px rgba(0,0,0,0.25)' };
const field: React.CSSProperties = { marginBottom: '0.875rem' };
const labelStyle: React.CSSProperties = { display: 'block', fontSize: '0.75rem', fontWeight: 600, color: 'var(--vz-text-secondary)', marginBottom: '0.25rem', textTransform: 'uppercase', letterSpacing: '0.03em' };
const gridTwo: React.CSSProperties = { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' };
const gridThree: React.CSSProperties = { display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.75rem' };

const TAB_CONFIG = [
    { key: 'basic', label: 'Basic Info', icon: <BiInfoCircle /> },
    { key: 'location', label: 'Location', icon: <BiMap /> },
    { key: 'contact', label: 'Contact', icon: <BiPhone /> },
    { key: 'operations', label: 'Operations', icon: <BiTime /> },
    { key: 'business', label: 'Business', icon: <BiBriefcase /> },
    { key: 'amenities', label: 'Amenities', icon: <BiGridAlt /> },
    { key: 'media', label: 'Media', icon: <BiImage /> },
];

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const CUISINE_OPTIONS = ['Indian', 'Continental', 'Asian', 'Chinese', 'Italian', 'Goan', 'Seafood', 'Mediterranean', 'Irish', 'British', 'Modern European', 'Asian Fusion', 'Pub Grub', 'Finger Food', 'Bombay Style'];
const MUSIC_OPTIONS = ['EDM', 'House', 'Techno', 'Commercial', 'Bollywood', 'Hip-Hop', 'Rock', 'Pop', 'Jazz', 'Acoustic', 'Deep House', 'Lounge', 'Chill', 'Irish Folk', 'Retro', 'Jukebox'];

export const INDIAN_STATES = [
    "Andaman and Nicobar Islands", "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", 
    "Chandigarh", "Chhattisgarh", "Dadra and Nagar Haveli and Daman and Diu", "Delhi", "Goa", 
    "Gujarat", "Haryana", "Himachal Pradesh", "Jammu and Kashmir", "Jharkhand", "Karnataka", 
    "Kerala", "Ladakh", "Lakshadweep", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", 
    "Mizoram", "Nagaland", "Odisha", "Puducherry", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", 
    "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal"
];

const INDIAN_CITIES = [
    "Agartala", "Agra", "Ahmedabad", "Ahmednagar", "Aizawl", "Ajmer", "Akbarpur", "Akola", "Aligarh", 
    "Allahabad", "Alwar", "Amarnath", "Amravati", "Amritsar", "Amroha", "Anand", "Anantapur", "Arrah", 
    "Asansol", "Aurangabad", "Avadi", "Bahadurgarh", "Bahraich", "Bally", "Bangalore", "Baranagar", 
    "Barasat", "Bardhaman", "Bareilly", "Bathinda", "Begusarai", "Belgaum", "Bellary", "Berhampur", 
    "Bettiah", "Bhagalpur", "Bharatpur", "Bhatpara", "Bhavnagar", "Bhilai", "Bhilwara", "Bhind", 
    "Bhiwandi", "Bhopal", "Bhubaneswar", "Bhusawal", "Bihar Sharif", "Bijapur", "Bikaner", "Bilaspur", 
    "Bokaro", "Bulandshahr", "Chandigarh", "Chandrapur", "Chennai", "Chhapra", "Coimbatore", "Cuttack", 
    "Darbhanga", "Davanagere", "Dehradun", "Delhi", "Deoghar", "Dewas", "Dhanbad", "Dhule", "Durg", 
    "Durgapur", "Eluru", "Erode", "Etawah", "Faridabad", "Farrukhabad", "Firozabad", "Gandhidham", 
    "Gaya", "Ghaziabad", "Goa", "Gonda", "Gopalpur", "Gorakhpur", "Gulbarga", "Guntakal", "Guntur", "Gurgaon", 
    "Guwahati", "Gwalior", "Haldia", "Haldwani", "Hapur", "Haridwar", "Hospet", "Howrah", "Hubli-Dharwad", 
    "Hyderabad", "Ichalkaranji", "Imphal", "Indore", "Jabalpur", "Jaipur", "Jalandhar", "Jalgaon", "Jalna", 
    "Jammu", "Jamnagar", "Jamshedpur", "Jhansi", "Jodhpur", "Junagadh", "Kadapa", "Kakinada", "Kalyan-Dombivli", 
    "Kamarhati", "Kanpur", "Karimnagar", "Karnal", "Khammam", "Khandwa", "Kharagpur", "Kochi", "Kolhapur", 
    "Kolkata", "Kollam", "Korba", "Kota", "Kozhikode", "Kulti", "Kurnool", "Latur", "Loni", "Lucknow", 
    "Ludhiana", "Madurai", "Maheshtala", "Malegaon", "Mangalore", "Mango", "Mathura", "Mau", "Meerut", 
    "Mira-Bhayandar", "Mirzapur", "Moradabad", "Morena", "Mumbai", "Munger", "Murwara", "Muzaffarnagar", 
    "Muzaffarpur", "Mysore", "Nadiad", "Nagercoil", "Nagpur", "Nanded", "Nandyal", "Nashik", "Navi Mumbai", 
    "Nellore", "New Delhi", "Nizamabad", "Noida", "Orai", "Ozhukarai", "Pali", "Panihati", "Panipat", "Parbhani", 
    "Patiala", "Patna", "Phusro", "Pimpri-Chinchwad", "Puducherry", "Pune", "Purnia", "Rae Bareli", "Raichur", 
    "Raipur", "Rajahmundry", "Rajkot", "Rajpur Sonarpur", "Ramagundam", "Rampur", "Ranchi", "Ratlam", "Rewa", 
    "Rohtak", "Rourkela", "Sagar", "Saharanpur", "Salem", "Sambalpur", "Sangli", "Satara", "Satna", 
    "Shahjahanpur", "Shivamogga", "Sikar", "Sikandarabad", "Silchar", "Siliguri", "Sonipat", "South Dumdum", 
    "Sri Ganganagar", "Srinagar", "Srirampore", "Surat", "Thane", "Thanjavur", "Thiruvananthapuram", "Thoothukudi", 
    "Thrissur", "Tiruchirappalli", "Tirunelveli", "Tirupati", "Tiruppur", "Tiruvottiyur", "Tumkur", "Udaipur", 
    "Ujjain", "Ulhasnagar", "Uluberia", "Vadodara", "Varanasi", "Vasai-Virar", "Vijayawada", "Vijayanagaram", 
    "Visakhapatnam", "Warangal"
];

const parse24To12 = (time24: string) => {
    if (!time24 || !time24.includes(':')) {
        return { hour: '07', minute: '00', period: 'PM' };
    }
    const [hStr, mStr] = time24.split(':');
    let h = parseInt(hStr, 10);
    const m = mStr.substring(0, 2);
    let period = 'AM';
    if (h >= 12) {
        period = 'PM';
        if (h > 12) h -= 12;
    }
    if (h === 0) {
        h = 12;
    }
    const hour = h.toString().padStart(2, '0');
    return { hour, minute: m, period };
};

const format12To24 = (hour: string, minute: string, period: string) => {
    let h = parseInt(hour, 10);
    if (period === 'PM' && h < 12) {
        h += 12;
    } else if (period === 'AM' && h === 12) {
        h = 0;
    }
    return `${h.toString().padStart(2, '0')}:${minute}`;
};

const TimePicker12: React.FC<{
    value: string;
    onChange: (val: string) => void;
}> = ({ value, onChange }) => {
    const { hour, minute, period } = parse24To12(value);

    const hours = Array.from({ length: 12 }, (_, i) => (i + 1).toString().padStart(2, '0'));
    const minutes = Array.from({ length: 60 }, (_, i) => i.toString().padStart(2, '0'));

    return (
        <div style={{ display: 'flex', gap: '0.375rem' }}>
            <select
                className="vz-form-control"
                value={hour}
                onChange={e => onChange(format12To24(e.target.value, minute, period))}
                style={{ flex: 1, minWidth: '60px', padding: '0.375rem 0.5rem', textAlign: 'center' }}
            >
                {hours.map(h => <option key={h} value={h}>{h}</option>)}
            </select>
            <span style={{ alignSelf: 'center', fontWeight: 'bold', color: 'var(--vz-text-muted)' }}>:</span>
            <select
                className="vz-form-control"
                value={minute}
                onChange={e => onChange(format12To24(hour, e.target.value, period))}
                style={{ flex: 1, minWidth: '60px', padding: '0.375rem 0.5rem', textAlign: 'center' }}
            >
                {minutes.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
            <select
                className="vz-form-control"
                value={period}
                onChange={e => onChange(format12To24(hour, minute, e.target.value))}
                style={{ flex: 1, minWidth: '65px', padding: '0.375rem 0.5rem', fontWeight: 600, color: 'var(--vz-primary)', background: 'rgba(var(--vz-primary-rgb), 0.05)', textAlign: 'center' }}
            >
                <option value="AM">AM</option>
                <option value="PM">PM</option>
            </select>
        </div>
    );
};

export const VenueForm: React.FC<VenueFormProps> = ({ venue, onClose, onSave }) => {
    const [activeTab, setActiveTab] = useState(0);
    const [form, setForm] = useState(getDefaultForm(venue));
    const [showCropModal, setShowCropModal] = useState(false);
    const [cropImage, setCropImage] = useState<string>('');
    const [showCloseConfirm, setShowCloseConfirm] = useState(false);

    // Update form when venue prop changes
    useEffect(() => {
        setForm(getDefaultForm(venue));
    }, [venue]);

    // Check if the form has any data entered (to decide whether to show discard warning)
    const isFormDirty = (): boolean => {
        const defaults = getDefaultForm(venue);
        return (
            form.name !== defaults.name ||
            form.addressLine1 !== defaults.addressLine1 ||
            form.city !== defaults.city ||
            form.phone !== defaults.phone ||
            form.cpName !== defaults.cpName ||
            form.description !== defaults.description
        );
    };

    const set = (key: string, val: any) => setForm(prev => ({ ...prev, [key]: val }));
    const setAmenity = (key: keyof VenueAmenities, val: boolean) =>
        setForm(prev => ({ ...prev, amenities: { ...prev.amenities, [key]: val } }));

    const toggleDay = (day: string) => {
        setForm((prev: VenueFormState) => ({
            ...prev,
            daysOpen: prev.daysOpen.includes(day) ? prev.daysOpen.filter((d: string) => d !== day) : [...prev.daysOpen, day],
        }));
    };

    const toggleMulti = (key: 'cuisineTypes' | 'musicTypes', val: string) => {
        setForm(prev => ({
            ...prev,
            [key]: (prev[key] as string[]).includes(val) ? (prev[key] as string[]).filter(v => v !== val) : [...(prev[key] as string[]), val],
        }));
    };

    const handleCoverUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        // Validate image format
        const validation = validateImageFile(file);
        if (!validation.valid) {
            toast.error(validation.error || 'Invalid image file');
            e.target.value = '';
            return;
        }

        try {
            // Auto-compress large image to 300KB
            const compressed = await compressImageIfNeeded(file, 300);
            const dataUrl = await fileToDataUrl(compressed);
            setCropImage(dataUrl);
            setShowCropModal(true);
            e.target.value = '';
        } catch (error) {
            toast.error('Failed to load image');
            console.error(error);
            e.target.value = '';
        }
    };

    const handleCropComplete = async (croppedFile: File) => {
        try {
            // Compress cropped result to under 300KB
            const finalFile = await compressImageIfNeeded(croppedFile, 300);
            const url = URL.createObjectURL(finalFile);
            setForm(prev => ({
                ...prev,
                media: { ...prev.media, coverImage: url },
                _coverFile: finalFile // Store actual file for backend
            }));
            setShowCropModal(false);
            setCropImage('');
            toast.success('Cover image updated & compressed successfully!');
        } catch (error) {
            toast.error('Failed to process image');
            console.error(error);
        }
    };

    const filterDuplicates = (newFiles: File[], existingFiles: File[]) => {
        const uniqueFiles: File[] = [];
        const seenBaseNames = new Set(existingFiles.map(f => f.name.replace(/\.[^.]+$/, '')));
        let duplicates = 0;

        for (const file of newFiles) {
            const baseName = file.name.replace(/\.[^.]+$/, '');
            if (!seenBaseNames.has(baseName)) {
                seenBaseNames.add(baseName);
                uniqueFiles.push(file);
            } else {
                duplicates++;
            }
        }
        
        if (duplicates > 0) {
            toast.error(`${duplicates} duplicate file(s) ignored.`);
        }
        return uniqueFiles;
    };

    const handlePhotosUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const rawFiles = Array.from(e.target.files || []);
        e.target.value = '';
        if (rawFiles.length === 0) return;

        const uniqueFiles = filterDuplicates(rawFiles, form._photoFiles || []);
        if (uniqueFiles.length === 0) return;

        const currentPhotos = form.media.photos || [];
        const remainingSlots = 20 - currentPhotos.length;
        const filesToProcess = uniqueFiles.slice(0, remainingSlots);
        if (uniqueFiles.length > remainingSlots) {
            toast.error(`Only ${remainingSlots} photo slot(s) remaining.`);
        }

        const { validFiles, errors } = await processImageFiles(filesToProcess);
        errors.forEach(err => toast.error(err));
        if (validFiles.length === 0) return;

        const newUrls = validFiles.map(f => URL.createObjectURL(f));
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, photos: [...(prev.media.photos || []), ...newUrls] },
            _photoFiles: [...(prev._photoFiles || []), ...validFiles],
        }));
    };

    const removePhoto = (index: number) => {
        setForm(prev => {
            const isBlob = (url: string) => typeof url === 'string' && url.startsWith('blob:');
            const newPhotos = [...(prev.media.photos || [])];
            const deletedUrl = newPhotos[index];
            newPhotos.splice(index, 1);

            const newFiles = prev._photoFiles ? [...prev._photoFiles] : [];
            if (deletedUrl && isBlob(deletedUrl)) {
                const blobIndex = (prev.media.photos || []).slice(0, index).filter(isBlob).length;
                newFiles.splice(blobIndex, 1);
            }

            return {
                ...prev,
                media: { ...prev.media, photos: newPhotos },
                _photoFiles: newFiles
            };
        });
    };

    const handleVideosUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
        const rawFiles = Array.from(e.target.files || []);
        e.target.value = '';
        if (rawFiles.length === 0) return;

        const uniqueFiles = filterDuplicates(rawFiles, form._videoFiles || []);
        if (uniqueFiles.length === 0) return;

        const currentVideos = form.media.videos || [];
        const remainingSlots = 20 - currentVideos.length;
        const filesToProcess = uniqueFiles.slice(0, remainingSlots);
        if (uniqueFiles.length > remainingSlots) {
            toast.error(`Only ${remainingSlots} video slot(s) remaining.`);
        }

        const { validFiles, errors } = processVideoFiles(filesToProcess);
        errors.forEach(err => toast.error(err));
        if (validFiles.length === 0) return;

        const newUrls = validFiles.map(f => URL.createObjectURL(f));
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, videos: [...(prev.media.videos || []), ...newUrls] },
            _videoFiles: [...(prev._videoFiles || []), ...validFiles],
        }));
    };

    const removeVideo = (index: number) => {
        setForm(prev => {
            const isBlob = (url: string) => typeof url === 'string' && url.startsWith('blob:');
            const newVideos = [...(prev.media.videos || [])];
            const deletedUrl = newVideos[index];
            newVideos.splice(index, 1);

            const newFiles = prev._videoFiles ? [...prev._videoFiles] : [];
            if (deletedUrl && isBlob(deletedUrl)) {
                const blobIndex = (prev.media.videos || []).slice(0, index).filter(isBlob).length;
                newFiles.splice(blobIndex, 1);
            }

            return {
                ...prev,
                media: { ...prev.media, videos: newVideos },
                _videoFiles: newFiles
            };
        });
    };

    // ── Food Menu handlers ──────────────────────────────────────────────────────
    const handleFoodMenusUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const rawFiles = Array.from(e.target.files || []);
        e.target.value = '';
        if (rawFiles.length === 0) return;

        const uniqueFiles = filterDuplicates(rawFiles, form._foodMenuFiles || []);
        if (uniqueFiles.length === 0) return;

        const current = form.media.foodMenus || [];
        const remaining = 20 - current.length;
        const toProcess = uniqueFiles.slice(0, remaining);
        if (uniqueFiles.length > remaining) toast.error(`Only ${remaining} slot(s) remaining for Food Menu.`);
        const { validFiles, errors } = await processImageFiles(toProcess);
        errors.forEach(err => toast.error(err));
        if (validFiles.length === 0) return;
        const newUrls = validFiles.map(f => URL.createObjectURL(f));
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, foodMenus: [...(prev.media.foodMenus || []), ...newUrls] },
            _foodMenuFiles: [...(prev._foodMenuFiles || []), ...validFiles],
        }));
    };

    const removeFoodMenu = (index: number) => {
        setForm(prev => {
            const isBlob = (url: string) => typeof url === 'string' && url.startsWith('blob:');
            const arr = [...(prev.media.foodMenus || [])];
            const deletedUrl = arr[index];
            arr.splice(index, 1);

            const files = prev._foodMenuFiles ? [...prev._foodMenuFiles] : [];
            if (deletedUrl && isBlob(deletedUrl)) {
                const blobIndex = (prev.media.foodMenus || []).slice(0, index).filter(isBlob).length;
                files.splice(blobIndex, 1);
            }
            return { ...prev, media: { ...prev.media, foodMenus: arr }, _foodMenuFiles: files };
        });
    };

    // ── Bar Menu handlers ────────────────────────────────────────────────────────
    const handleBarMenusUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const rawFiles = Array.from(e.target.files || []);
        e.target.value = '';
        if (rawFiles.length === 0) return;

        const uniqueFiles = filterDuplicates(rawFiles, form._barMenuFiles || []);
        if (uniqueFiles.length === 0) return;

        const current = form.media.barMenus || [];
        const remaining = 20 - current.length;
        const toProcess = uniqueFiles.slice(0, remaining);
        if (uniqueFiles.length > remaining) toast.error(`Only ${remaining} slot(s) remaining for Bar Menu.`);
        const { validFiles, errors } = await processImageFiles(toProcess);
        errors.forEach(err => toast.error(err));
        if (validFiles.length === 0) return;
        const newUrls = validFiles.map(f => URL.createObjectURL(f));
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, barMenus: [...(prev.media.barMenus || []), ...newUrls] },
            _barMenuFiles: [...(prev._barMenuFiles || []), ...validFiles],
        }));
    };

    const removeBarMenu = (index: number) => {
        setForm(prev => {
            const isBlob = (url: string) => typeof url === 'string' && url.startsWith('blob:');
            const arr = [...(prev.media.barMenus || [])];
            const deletedUrl = arr[index];
            arr.splice(index, 1);

            const files = prev._barMenuFiles ? [...prev._barMenuFiles] : [];
            if (deletedUrl && isBlob(deletedUrl)) {
                const blobIndex = (prev.media.barMenus || []).slice(0, index).filter(isBlob).length;
                files.splice(blobIndex, 1);
            }
            return { ...prev, media: { ...prev.media, barMenus: arr }, _barMenuFiles: files };
        });
    };

    // ── Beverage Menu handlers ───────────────────────────────────────────────────
    const handleBeverageMenusUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const rawFiles = Array.from(e.target.files || []);
        e.target.value = '';
        if (rawFiles.length === 0) return;

        const uniqueFiles = filterDuplicates(rawFiles, form._beverageMenuFiles || []);
        if (uniqueFiles.length === 0) return;

        const current = form.media.beverageMenus || [];
        const remaining = 20 - current.length;
        const toProcess = uniqueFiles.slice(0, remaining);
        if (uniqueFiles.length > remaining) toast.error(`Only ${remaining} slot(s) remaining for Beverage Menu.`);
        const { validFiles, errors } = await processImageFiles(toProcess);
        errors.forEach(err => toast.error(err));
        if (validFiles.length === 0) return;
        const newUrls = validFiles.map(f => URL.createObjectURL(f));
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, beverageMenus: [...(prev.media.beverageMenus || []), ...newUrls] },
            _beverageMenuFiles: [...(prev._beverageMenuFiles || []), ...validFiles],
        }));
    };

    const removeBeverageMenu = (index: number) => {
        setForm(prev => {
            const isBlob = (url: string) => typeof url === 'string' && url.startsWith('blob:');
            const arr = [...(prev.media.beverageMenus || [])];
            const deletedUrl = arr[index];
            arr.splice(index, 1);

            const files = prev._beverageMenuFiles ? [...prev._beverageMenuFiles] : [];
            if (deletedUrl && isBlob(deletedUrl)) {
                const blobIndex = (prev.media.beverageMenus || []).slice(0, index).filter(isBlob).length;
                files.splice(blobIndex, 1);
            }
            return { ...prev, media: { ...prev.media, beverageMenus: arr }, _beverageMenuFiles: files };
        });
    };

    // ── Party Packages handlers ───────────────────────────────────────────────────
    const handlePartyPackagesUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const rawFiles = Array.from(e.target.files || []);
        e.target.value = '';
        if (rawFiles.length === 0) return;

        const uniqueFiles = filterDuplicates(rawFiles, form._partyPackagesFiles || []);
        if (uniqueFiles.length === 0) return;

        const current = form.media.partyPackages || [];
        const remaining = 20 - current.length;
        const toProcess = uniqueFiles.slice(0, remaining);
        if (uniqueFiles.length > remaining) toast.error(`Only ${remaining} slot(s) remaining for Party Packages.`);
        const { validFiles, errors } = await processImageFiles(toProcess);
        errors.forEach(err => toast.error(err));
        if (validFiles.length === 0) return;
        const newUrls = validFiles.map(f => URL.createObjectURL(f));
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, partyPackages: [...(prev.media.partyPackages || []), ...newUrls] },
            _partyPackagesFiles: [...(prev._partyPackagesFiles || []), ...validFiles],
        }));
    };

    const removePartyPackages = (index: number) => {
        setForm(prev => {
            const isBlob = (url: string) => typeof url === 'string' && url.startsWith('blob:');
            const arr = [...(prev.media.partyPackages || [])];
            const deletedUrl = arr[index];
            arr.splice(index, 1);

            const files = prev._partyPackagesFiles ? [...prev._partyPackagesFiles] : [];
            if (deletedUrl && isBlob(deletedUrl)) {
                const blobIndex = (prev.media.partyPackages || []).slice(0, index).filter(isBlob).length;
                files.splice(blobIndex, 1);
            }
            return { ...prev, media: { ...prev.media, partyPackages: arr }, _partyPackagesFiles: files };
        });
    };

    const removeCover = () => {
        setForm(prev => ({
            ...prev,
            media: { ...prev.media, coverImage: '' },
            _coverFile: null
        }));
    };

    const [formErrors, setFormErrors] = useState<Record<string, string>>({});

    /** Validate all required fields. Returns true if valid. */
    const validate = (): boolean => {
        const errors: Record<string, string> = {};

        // Only Venue Name is mandatory
        if (!form.name.trim()) errors.name = 'Venue Name is required.';

        setFormErrors(errors);

        if (Object.keys(errors).length > 0) {
            setActiveTab(0); // Name is on Basic Info tab
            return false;
        }
        return true;
    };

    const [isSubmitting, setIsSubmitting] = useState(false);

    const handleSubmit = async () => {
        if (!validate()) return;
        if (isSubmitting) return;
        setIsSubmitting(true);
        try {
            await onSave(form);
        } finally {
            setIsSubmitting(false);
        }
    };

    /** Helper: render inline error below a field */
    const errMsg = (field: string) =>
        formErrors[field]
            ? <span style={{ display: 'block', color: '#ef4444', fontSize: '0.72rem', marginTop: '0.2rem' }}>⚠ {formErrors[field]}</span>
            : null;

    /* ─── Tab content renderers ─── */

    const renderBasicInfo = () => (
        <div>
            <div style={field}>
                <label style={labelStyle}>Venue Name *</label>
                <input
                    className="vz-form-control"
                    placeholder="e.g. Club Infinity"
                    value={form.name}
                    onChange={e => { set('name', e.target.value); if (formErrors.name) setFormErrors(p => ({...p, name: ''})); }}
                    style={formErrors.name ? { borderColor: '#ef4444' } : {}}
                />
                {errMsg('name')}
            </div>
            <div style={field}>
                <label style={labelStyle}>Tagline</label>
                <input className="vz-form-control" placeholder="e.g. Where the Night Never Ends" value={form.tagline} onChange={e => set('tagline', e.target.value)} />
            </div>
            <div style={field}>
                <label style={labelStyle}>Description (Format with Emojis)</label>
                <textarea 
                    className="vz-form-control" 
                    rows={6} 
                    placeholder={`e.g.\n🪙 ₹3100 for two\n🍽️ North Indian, Asian, Continental\n📍 4th Floor, Sai Apex, Datta Mandir Chowk, Viman Nagar, Pune`} 
                    value={form.description} 
                    onChange={e => set('description', e.target.value)} 
                    style={{ resize: 'vertical', minHeight: 120 }} 
                />
                <span style={{ display: 'block', fontSize: '0.72rem', color: 'var(--vz-text-secondary)', marginTop: '0.4rem' }}>
                    Tip: Use emojis (Win + .) to format the about section like: 🪙 Cost for two | 🍽️ Cuisines | 📍 Address
                </span>
            </div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Category</label>
                    <select
                        className="vz-form-control"
                        value={form.category}
                        onChange={e => set('category', e.target.value)}
                    >
                        {(Object.keys(CATEGORY_CONFIG) as VenueCategory[]).map(cat => (
                            <option key={cat} value={cat}>{CATEGORY_CONFIG[cat].label}</option>
                        ))}
                    </select>
                </div>
                <div style={field}>
                    <label style={labelStyle}>Status *</label>
                    <select
                        className="vz-form-control"
                        value={form.status}
                        onChange={e => set('status', e.target.value)}
                    >
                        <option value="draft">Draft</option>
                        <option value="submitted">Submitted</option>
                        <option value="pending_confirmation">Pending Confirmation</option>
                        <option value="pending">Pending</option>
                        <option value="approved">Approved</option>
                        <option value="live">Live</option>
                        <option value="rejected">Rejected</option>
                        <option value="suspended">Suspended</option>
                        <option value="deactivated">Deactivated</option>
                    </select>

                    {/* Status hint messages */}
                    {form.status === 'live' && venue?.status !== 'live' && (
                        <span style={{ display: 'block', fontSize: '0.72rem', color: '#22c55e', marginTop: '0.2rem' }}>
                            🟢 Venue will be made Live immediately upon saving.
                        </span>
                    )}
                    {form.status === 'live' && venue?.status === 'live' && (
                        <span style={{ display: 'block', fontSize: '0.72rem', color: '#22c55e', marginTop: '0.2rem' }}>
                            🟢 Venue is currently Live.
                        </span>
                    )}
                    {form.status === 'suspended' && (
                        <span style={{ display: 'block', fontSize: '0.72rem', color: '#f59e0b', marginTop: '0.2rem' }}>
                            ⏸️ Venue will be Suspended.
                        </span>
                    )}
                    {form.status === 'deactivated' && (
                        <span style={{ display: 'block', fontSize: '0.72rem', color: '#ef4444', marginTop: '0.2rem' }}>
                            🔴 Venue will be Deactivated.
                        </span>
                    )}
                </div>
            </div>
            <div style={field}>
                <label style={labelStyle}>Tags (comma separated)</label>
                <input className="vz-form-control" placeholder="e.g. nightclub, dj, edm, vip" value={form.tags} onChange={e => set('tags', e.target.value)} />
            </div>
            <div style={{ display: 'flex', gap: '1.5rem', marginTop: '0.5rem' }}>
                {([
                    { key: 'isActive', label: 'Active' },
                    { key: 'isFeatured', label: 'Featured' },
                    { key: 'isPremium', label: 'Premium' },
                ] as const).map(flag => (
                    <label key={flag.key} style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', cursor: 'pointer', fontSize: '0.8125rem', fontWeight: 500, color: 'var(--vz-text-primary)' }}>
                        <input
                            type="checkbox"
                            checked={form[flag.key] as boolean}
                            onChange={e => set(flag.key, e.target.checked)}
                            style={{ width: 16, height: 16, accentColor: 'var(--vz-primary)' }}
                        />
                        {flag.label}
                    </label>
                ))}
            </div>
        </div>
    );

    const renderLocation = () => (
        <div>
            <div style={field}>
                <label style={labelStyle}>Address Line 1 *</label>
                <input
                    className="vz-form-control"
                    placeholder="Street address, building"
                    value={form.addressLine1}
                    onChange={e => { set('addressLine1', e.target.value); if (formErrors.addressLine1) setFormErrors(p => ({...p, addressLine1: ''})); }}
                    style={formErrors.addressLine1 ? { borderColor: '#ef4444' } : {}}
                />
                {errMsg('addressLine1')}
            </div>
            <div style={field}>
                <label style={labelStyle}>Address Line 2</label>
                <input className="vz-form-control" placeholder="Floor, wing, near..." value={form.addressLine2} onChange={e => set('addressLine2', e.target.value)} />
            </div>
            <div style={gridThree}>
                <div style={field}>
                    <label style={labelStyle}>Area *</label>
                    <select
                        className="vz-form-control"
                        value={form.area}
                        onChange={e => { set('area', e.target.value); if (formErrors.area) setFormErrors(p => ({...p, area: ''})); }}
                        style={formErrors.area ? { borderColor: '#ef4444' } : {}}
                    >
                        <option value="">Select Area</option>
                        <option value="Wakad">Wakad</option>
                        <option value="Hinjewadi">Hinjewadi</option>
                        <option value="Baner">Baner</option>
                        <option value="Aundh">Aundh</option>
                        <option value="Koregaon park">Koregaon park</option>
                        <option value="Kalyani Nagar">Kalyani Nagar</option>
                        <option value="Camp">Camp</option>
                        <option value="Shivaji nagar">Shivaji nagar</option>
                        <option value="Viman Nagar">Viman Nagar</option>
                        <option value="Balewadi">Balewadi</option>
                        <option value="Pune station">Pune station</option>
                        <option value="Pune">Pune</option>
                    </select>
                    {errMsg('area')}
                </div>
                <div style={field}>
                    <label style={labelStyle}>Display Order</label>
                    <input
                        type="number"
                        min="0"
                        className="vz-form-control"
                        placeholder="0"
                        value={form.displayOrder}
                        onChange={e => set('displayOrder', e.target.value.replace(/\D/g, ''))}
                    />
                </div>
                <div style={field}>
                    <label style={labelStyle}>City *</label>
                    <select
                        className="vz-form-control"
                        value={form.city}
                        onChange={e => { set('city', e.target.value); if (formErrors.city) setFormErrors(p => ({...p, city: ''})); }}
                        style={formErrors.city ? { borderColor: '#ef4444', backgroundColor: 'transparent' } : { backgroundColor: 'transparent' }}
                    >
                        <option value="" disabled>Select a city...</option>
                        {INDIAN_CITIES.map(c => <option key={c} value={c}>{c}</option>)}
                    </select>
                    {errMsg('city')}
                </div>
                <div style={field}>
                    <label style={labelStyle}>State *</label>
                    <select
                        className="vz-form-control"
                        value={form.state}
                        onChange={e => { set('state', e.target.value); if (formErrors.state) setFormErrors(p => ({...p, state: ''})); }}
                        style={formErrors.state ? { borderColor: '#ef4444', backgroundColor: 'transparent' } : { backgroundColor: 'transparent' }}
                    >
                        <option value="" disabled>Select a state...</option>
                        {INDIAN_STATES.map(s => <option key={s} value={s}>{s}</option>)}
                    </select>
                    {errMsg('state')}
                </div>
            </div>
            <div style={gridThree}>
                <div style={field}>
                    <label style={labelStyle}>Pincode *</label>
                    <input
                        className="vz-form-control"
                        placeholder="e.g. 560066"
                        value={form.pincode}
                        onChange={e => { set('pincode', e.target.value); if (formErrors.pincode) setFormErrors(p => ({...p, pincode: ''})); }}
                        style={formErrors.pincode ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('pincode')}
                </div>
                <div style={field}>
                    <label style={labelStyle}>Country</label>
                    <input className="vz-form-control" value={form.country} onChange={e => set('country', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Nearest Landmark</label>
                    <input className="vz-form-control" placeholder="e.g. Phoenix Mall" value={form.nearestLandmark} onChange={e => set('nearestLandmark', e.target.value)} />
                </div>
            </div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Latitude</label>
                    <input className="vz-form-control" type="number" step="any" placeholder="e.g. 12.9969" value={form.latitude} onChange={e => set('latitude', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Longitude</label>
                    <input className="vz-form-control" type="number" step="any" placeholder="e.g. 77.7499" value={form.longitude} onChange={e => set('longitude', e.target.value)} />
                </div>
            </div>
            <div style={field}>
                <label style={labelStyle}>Directions</label>
                <textarea className="vz-form-control" rows={2} placeholder="How to reach the venue..." value={form.directions} onChange={e => set('directions', e.target.value)} style={{ resize: 'vertical' }} />
            </div>
        </div>
    );

    const renderContact = () => (
        <div>
            {/* Venue Contact */}
            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', marginBottom: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Venue Contact</div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>Phone</label><input className="vz-form-control" placeholder="e.g. 080-41234567" value={form.phone} onChange={e => set('phone', e.target.value)} /></div>
                <div style={field}>
                    <label style={labelStyle}>Mobile *</label>
                    <input
                        className="vz-form-control"
                        placeholder="e.g. 9876543210"
                        value={form.mobile}
                        onChange={e => { set('mobile', e.target.value); if (formErrors.mobile) setFormErrors(p => ({...p, mobile: ''})); }}
                        style={formErrors.mobile ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('mobile')}
                </div>
            </div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>WhatsApp</label><input className="vz-form-control" placeholder="WhatsApp number" value={form.whatsapp} onChange={e => set('whatsapp', e.target.value)} /></div>
                <div style={field}>
                    <label style={labelStyle}>Email *</label>
                    <input
                        className="vz-form-control"
                        type="email"
                        placeholder="bookings@venue.in"
                        value={form.email}
                        onChange={e => { set('email', e.target.value); if (formErrors.email) setFormErrors(p => ({...p, email: ''})); }}
                        style={formErrors.email ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('email')}
                </div>
            </div>
            <div style={gridThree}>
                <div style={field}><label style={labelStyle}>Website</label><input className="vz-form-control" placeholder="https://..." value={form.website} onChange={e => set('website', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Instagram</label><input className="vz-form-control" placeholder="@handle" value={form.instagram} onChange={e => set('instagram', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Facebook</label><input className="vz-form-control" placeholder="Page name" value={form.facebook} onChange={e => set('facebook', e.target.value)} /></div>
            </div>

            {/* Primary Contact Person */}
            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', margin: '1.25rem 0 0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Primary Contact Person</div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Name *</label>
                    <input
                        className="vz-form-control"
                        placeholder="Full name"
                        value={form.cpName}
                        onChange={e => { set('cpName', e.target.value); if (formErrors.cpName) setFormErrors(p => ({...p, cpName: ''})); }}
                        style={formErrors.cpName ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('cpName')}
                </div>
                <div style={field}><label style={labelStyle}>Designation</label><input className="vz-form-control" placeholder="e.g. Manager" value={form.cpDesignation} onChange={e => set('cpDesignation', e.target.value)} /></div>
            </div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>Mobile</label><input className="vz-form-control" placeholder="Mobile number" value={form.cpMobile} onChange={e => set('cpMobile', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Email</label><input className="vz-form-control" type="email" placeholder="Email" value={form.cpEmail} onChange={e => set('cpEmail', e.target.value)} /></div>
            </div>

            {/* Alternate Contact Person */}
            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-text-muted)', margin: '1.25rem 0 0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Alternate Contact Person</div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>Name</label><input className="vz-form-control" placeholder="Full name" value={form.altCpName} onChange={e => set('altCpName', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Designation</label><input className="vz-form-control" placeholder="e.g. Events Head" value={form.altCpDesignation} onChange={e => set('altCpDesignation', e.target.value)} /></div>
            </div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>Mobile</label><input className="vz-form-control" placeholder="Mobile number" value={form.altCpMobile} onChange={e => set('altCpMobile', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Email</label><input className="vz-form-control" type="email" placeholder="Email" value={form.altCpEmail} onChange={e => set('altCpEmail', e.target.value)} /></div>
            </div>
        </div>
    );

    const renderOperations = () => (
        <div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Opening Time *</label>
                    <TimePicker12 value={form.openingTime} onChange={val => set('openingTime', val)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Closing Time *</label>
                    <TimePicker12 value={form.closingTime} onChange={val => set('closingTime', val)} />
                </div>
            </div>
            <div style={field}>
                <label style={labelStyle}>Days Open</label>
                <div style={{ display: 'flex', gap: '0.375rem', flexWrap: 'wrap' }}>
                    {DAYS.map(day => (
                        <button
                            type="button"
                            key={day}
                            onClick={() => toggleDay(day)}
                            style={{
                                padding: '0.375rem 0.75rem',
                                borderRadius: 'var(--vz-radius)',
                                border: `1.5px solid ${form.daysOpen.includes(day) ? 'var(--vz-primary)' : 'var(--vz-border-color)'}`,
                                background: form.daysOpen.includes(day) ? 'rgba(var(--vz-primary-rgb), 0.1)' : 'transparent',
                                color: form.daysOpen.includes(day) ? 'var(--vz-primary)' : 'var(--vz-text-secondary)',
                                fontSize: '0.75rem',
                                fontWeight: 600,
                                cursor: 'pointer',
                                fontFamily: 'var(--vz-font)',
                                transition: 'all 0.2s ease',
                            }}
                        >{day}</button>
                    ))}
                </div>
            </div>
            <div style={field}>
                <label style={labelStyle}>Holidays / Closed Dates (comma separated YYYY-MM-DD)</label>
                <input className="vz-form-control" placeholder="e.g. 2026-08-15, 2026-12-25" value={form.closedDates} onChange={e => set('closedDates', e.target.value)} />
            </div>
            <div style={gridThree}>
                <div style={field}>
                    <label style={labelStyle}>Seating Capacity *</label>
                    <input className="vz-form-control" type="number" placeholder="e.g. 150" value={form.seatingCapacity} onChange={e => set('seatingCapacity', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Standing Capacity</label>
                    <input className="vz-form-control" type="number" placeholder="e.g. 500" value={form.standingCapacity} onChange={e => set('standingCapacity', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Age Limit</label>
                    <input className="vz-form-control" type="number" placeholder="e.g. 21" value={form.ageLimit} onChange={e => set('ageLimit', e.target.value)} />
                </div>
            </div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Cover Charge (Male) ₹</label>
                    <input className="vz-form-control" type="number" placeholder="e.g. 2000" value={form.coverChargeMale} onChange={e => set('coverChargeMale', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Cover Charge (Female) ₹</label>
                    <input className="vz-form-control" type="number" placeholder="e.g. 1500" value={form.coverChargeFemale} onChange={e => set('coverChargeFemale', e.target.value)} />
                </div>
            </div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Discount Percentage % *</label>
                    <input 
                        className="vz-form-control" 
                        type="number" step="0.01" placeholder="e.g. 10" 
                        value={form.discountPercentage} 
                        onChange={e => { set('discountPercentage', e.target.value); if (formErrors.discountPercentage) setFormErrors(p => ({...p, discountPercentage: ''})); }}
                        style={formErrors.discountPercentage ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('discountPercentage')}
                </div>
                <div style={field}>
                    <label style={labelStyle}>Table Booking Charges ₹ *</label>
                    <input 
                        className="vz-form-control" 
                        type="number" step="0.01" placeholder="e.g. 500" 
                        value={form.tableBookingCharges} 
                        onChange={e => { set('tableBookingCharges', e.target.value); if (formErrors.tableBookingCharges) setFormErrors(p => ({...p, tableBookingCharges: ''})); }}
                        style={formErrors.tableBookingCharges ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('tableBookingCharges')}
                </div>
                <div style={field}>
                    <label style={labelStyle}>Couple Entry Fee ₹</label>
                    <input 
                        className="vz-form-control" 
                        type="number" step="0.01" placeholder="e.g. 0" 
                        value={form.coupleEntryFee} 
                        onChange={e => { set('coupleEntryFee', e.target.value); if (formErrors.coupleEntryFee) setFormErrors(p => ({...p, coupleEntryFee: ''})); }}
                        style={formErrors.coupleEntryFee ? { borderColor: '#ef4444' } : {}}
                    />
                    {errMsg('coupleEntryFee')}
                </div>
            </div>
            <div style={field}>
                <label style={labelStyle}>Dress Code</label>
                <input className="vz-form-control" placeholder="e.g. Smart Casual - No Shorts, Slippers" value={form.dressCode} onChange={e => set('dressCode', e.target.value)} />
            </div>
            {/* Cuisine Types */}
            <div style={field}>
                <label style={labelStyle}>Cuisine Types</label>
                <div style={{ display: 'flex', gap: '0.375rem', flexWrap: 'wrap' }}>
                    {CUISINE_OPTIONS.map(c => (
                        <button
                            type="button" key={c}
                            onClick={() => toggleMulti('cuisineTypes', c)}
                            style={{
                                padding: '0.25rem 0.625rem',
                                borderRadius: '999px',
                                border: `1.5px solid ${form.cuisineTypes.includes(c) ? 'var(--vz-primary)' : 'var(--vz-border-color)'}`,
                                background: form.cuisineTypes.includes(c) ? 'rgba(var(--vz-primary-rgb), 0.1)' : 'transparent',
                                color: form.cuisineTypes.includes(c) ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                                fontSize: '0.6875rem', fontWeight: 500, cursor: 'pointer', fontFamily: 'var(--vz-font)', transition: 'all 0.2s ease',
                            }}
                        >{c}</button>
                    ))}
                </div>
            </div>
            {/* Music Types */}
            <div style={field}>
                <label style={labelStyle}>Music Types</label>
                <div style={{ display: 'flex', gap: '0.375rem', flexWrap: 'wrap' }}>
                    {MUSIC_OPTIONS.map(m => (
                        <button
                            type="button" key={m}
                            onClick={() => toggleMulti('musicTypes', m)}
                            style={{
                                padding: '0.25rem 0.625rem',
                                borderRadius: '999px',
                                border: `1.5px solid ${form.musicTypes.includes(m) ? 'var(--vz-success)' : 'var(--vz-border-color)'}`,
                                background: form.musicTypes.includes(m) ? 'rgba(var(--vz-success-rgb), 0.1)' : 'transparent',
                                color: form.musicTypes.includes(m) ? 'var(--vz-success)' : 'var(--vz-text-muted)',
                                fontSize: '0.6875rem', fontWeight: 500, cursor: 'pointer', fontFamily: 'var(--vz-font)', transition: 'all 0.2s ease',
                            }}
                        >{m}</button>
                    ))}
                </div>
            </div>
        </div>
    );

    const renderBusiness = () => (
        <div>
            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', marginBottom: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Tax & Registration</div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>PAN Number</label><input className="vz-form-control" placeholder="e.g. AAECI1234K" value={form.panNumber} onChange={e => set('panNumber', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>GST Number</label><input className="vz-form-control" placeholder="e.g. 29AAECI1234K1ZB" value={form.gstNumber} onChange={e => set('gstNumber', e.target.value)} /></div>
            </div>

            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', margin: '1.25rem 0 0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Licenses & Certificates</div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>FSSAI License</label><input className="vz-form-control" placeholder="Food license number" value={form.fssaiLicense} onChange={e => set('fssaiLicense', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Liquor License</label><input className="vz-form-control" placeholder="Liquor license number" value={form.liquorLicense} onChange={e => set('liquorLicense', e.target.value)} /></div>
            </div>
            <div style={gridTwo}>
                <div style={field}><label style={labelStyle}>Fire Safety Certificate</label><input className="vz-form-control" placeholder="Fire NOC number" value={form.fireSafetyCert} onChange={e => set('fireSafetyCert', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Trade License</label><input className="vz-form-control" placeholder="Trade license number" value={form.tradeLicense} onChange={e => set('tradeLicense', e.target.value)} /></div>
            </div>

            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', margin: '1.25rem 0 0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Bank Details</div>
            <div style={gridThree}>
                <div style={field}><label style={labelStyle}>Bank Name</label><input className="vz-form-control" placeholder="e.g. HDFC Bank" value={form.bankName} onChange={e => set('bankName', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>Account Number</label><input className="vz-form-control" placeholder="Account number" value={form.bankAccountNumber} onChange={e => set('bankAccountNumber', e.target.value)} /></div>
                <div style={field}><label style={labelStyle}>IFSC Code</label><input className="vz-form-control" placeholder="e.g. HDFC0001234" value={form.bankIFSC} onChange={e => set('bankIFSC', e.target.value)} /></div>
            </div>
        </div>
    );

    const renderAmenities = () => (
        <div>
            <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)', marginBottom: '1rem' }}>
                Toggle the amenities available at this venue.
            </p>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                {(Object.keys(AMENITY_CONFIG) as (keyof VenueAmenities)[]).map(key => (
                    <label
                        key={key}
                        style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.625rem',
                            padding: '0.625rem 0.875rem',
                            borderRadius: 'var(--vz-radius)',
                            border: `1.5px solid ${form.amenities[key] ? 'var(--vz-primary)' : 'var(--vz-border-color)'}`,
                            background: form.amenities[key] ? 'rgba(var(--vz-primary-rgb), 0.06)' : 'transparent',
                            cursor: 'pointer',
                            transition: 'all 0.2s ease',
                        }}
                    >
                        <input
                            type="checkbox"
                            checked={form.amenities[key]}
                            onChange={e => setAmenity(key, e.target.checked)}
                            style={{ width: 16, height: 16, accentColor: 'var(--vz-primary)' }}
                        />
                        <span style={{ fontSize: '1rem' }}>{AMENITY_CONFIG[key].icon}</span>
                        <span style={{ fontSize: '0.8125rem', fontWeight: form.amenities[key] ? 600 : 400, color: form.amenities[key] ? 'var(--vz-primary)' : 'var(--vz-text-secondary)' }}>
                            {AMENITY_CONFIG[key].label}
                        </span>
                    </label>
                ))}
            </div>
        </div>
    );

    const renderMedia = () => {
        const photos = form.media?.photos || [];
        return (
            <div>
                {/* ── Validation info banner ───────────────────────────────── */}
                <div style={{
                    marginBottom: '1rem',
                    padding: '0.75rem 1rem',
                    background: 'rgba(var(--vz-primary-rgb), 0.06)',
                    border: '1px solid rgba(var(--vz-primary-rgb), 0.2)',
                    borderRadius: 'var(--vz-radius)',
                    fontSize: '0.75rem',
                    color: 'var(--vz-text-secondary)',
                    lineHeight: 1.6,
                }}>
                    <strong style={{ color: 'var(--vz-primary)' }}>📋 Upload Guidelines</strong>
                    <span style={{ marginLeft: '0.5rem' }}>
                        Images: <strong>JPG, JPEG, PNG, WEBP</strong> only · Auto-compressed to ≤ 300KB &nbsp;|&nbsp;
                        Videos: <strong>MP4, MOV, AVI</strong> only
                    </span>
                </div>

                <div style={sectionTitle}>Header / Cover Image</div>
                <div style={{ marginBottom: '1.25rem' }}>
                    {form.media?.coverImage ? (
                        <div style={{ position: 'relative', width: '100%', paddingBottom: '30%', borderRadius: 'var(--vz-radius)', overflow: 'hidden', background: '#f8f9fa' }}>
                            <img src={form.media.coverImage} alt="Cover" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
                            <button type="button" onClick={removeCover} style={{ position: 'absolute', top: 8, right: 8, width: 32, height: 32, borderRadius: '50%', background: 'rgba(255,255,255,0.9)', color: 'var(--vz-danger)', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: '0 2px 8px rgba(0,0,0,0.1)' }}><BiTrash /></button>
                        </div>
                    ) : (
                        <label style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '2rem', border: '2px dashed var(--vz-border-color)', borderRadius: 'var(--vz-radius)', cursor: 'pointer', background: 'var(--vz-body-bg)', transition: 'all 0.2s ease' }}>
                            <BiUpload style={{ fontSize: '2rem', color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }} />
                            <span style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>Click to upload cover image</span>
                            <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', marginTop: '0.25rem' }}>Recommended: 1920x1080px · JPG, JPEG, PNG, WEBP · Auto-compressed to 300KB</span>
                            <input type="file" accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp" onChange={handleCoverUpload} style={{ display: 'none' }} />
                        </label>
                    )}
                </div>

                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.75rem', marginTop: '1.5rem' }}>
                    <div style={sectionTitle}>Gallery Photos ({photos.length}/20)</div>
                    {photos.length < 20 && (
                        <label style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', padding: '0.375rem 0.75rem', borderRadius: 'var(--vz-radius)', background: 'rgba(var(--vz-primary-rgb), 0.1)', color: 'var(--vz-primary)', fontSize: '0.75rem', fontWeight: 600, cursor: 'pointer', transition: 'all 0.2s ease' }}>
                            <BiPlus /> Add Photos
                            <input type="file" accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp" multiple onChange={handlePhotosUpload} style={{ display: 'none' }} />
                        </label>
                    )}
                </div>

                {photos.length > 0 ? (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))', gap: '0.75rem' }}>
                        {photos.map((url: string, idx: number) => (
                            <div key={idx} style={{ position: 'relative', width: '100%', paddingBottom: '100%', borderRadius: 'var(--vz-radius)', overflow: 'hidden', background: '#f8f9fa', border: '1px solid var(--vz-border-color)' }}>
                                <img src={url} alt={`Gallery ${idx + 1}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
                                <button type="button" onClick={() => removePhoto(idx)} style={{ position: 'absolute', top: 4, right: 4, width: 24, height: 24, borderRadius: '50%', background: 'rgba(255,255,255,0.9)', color: 'var(--vz-danger)', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}><BiX /></button>
                            </div>
                        ))}
                        {photos.length < 20 && (
                            <label style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', width: '100%', paddingBottom: '100%', position: 'relative', border: '2px dashed var(--vz-border-color)', borderRadius: 'var(--vz-radius)', cursor: 'pointer', background: 'var(--vz-body-bg)', transition: 'all 0.2s ease' }}>
                                <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                                    <BiUpload style={{ fontSize: '1.5rem', color: 'var(--vz-text-muted)', marginBottom: '0.25rem' }} />
                                    <span style={{ fontSize: '0.6875rem', fontWeight: 600, color: 'var(--vz-text-muted)' }}>Add more</span>
                                </div>
                                <input type="file" accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp" multiple onChange={handlePhotosUpload} style={{ display: 'none' }} />
                            </label>
                        )}
                    </div>
                ) : (
                    <div style={{ padding: '2rem', textAlign: 'center', border: '1px dashed var(--vz-border-color)', borderRadius: 'var(--vz-radius)', background: 'var(--vz-body-bg)' }}>
                        <BiImage style={{ fontSize: '2rem', color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }} />
                        <p style={{ margin: 0, fontSize: '0.8125rem', color: 'var(--vz-text-secondary)' }}>No photos added yet. Upload up to 20 images for the venue gallery.</p>
                    </div>
                )}

                {/* ── Menu Sections ───────────────────────────────────────────── */}
                {([
                    {
                        key: 'foodMenus' as const,
                        label: '🍽️ Food Menu',
                        color: '#f59e0b',
                        colorBg: 'rgba(245,158,11,0.08)',
                        colorBorder: 'rgba(245,158,11,0.25)',
                        files: form.media?.foodMenus || [],
                        handler: handleFoodMenusUpload,
                        remover: removeFoodMenu,
                        fileKey: '_foodMenuFiles',
                    },
                    {
                        key: 'barMenus' as const,
                        label: '🍺 Bar Menu',
                        color: '#8b5cf6',
                        colorBg: 'rgba(139,92,246,0.08)',
                        colorBorder: 'rgba(139,92,246,0.25)',
                        files: form.media?.barMenus || [],
                        handler: handleBarMenusUpload,
                        remover: removeBarMenu,
                        fileKey: '_barMenuFiles',
                    },
                    {
                        key: 'beverageMenus' as const,
                        label: '🥤 Beverage Menu',
                        color: '#06b6d4',
                        colorBg: 'rgba(6,182,212,0.08)',
                        colorBorder: 'rgba(6,182,212,0.25)',
                        files: form.media?.beverageMenus || [],
                        handler: handleBeverageMenusUpload,
                        remover: removeBeverageMenu,
                        fileKey: '_beverageMenuFiles',
                    },
                    {
                        key: 'partyPackages' as const,
                        label: '🎉 Party Packages',
                        color: '#f59e0b',
                        colorBg: 'rgba(245,158,11,0.08)',
                        colorBorder: 'rgba(245,158,11,0.25)',
                        files: form.media?.partyPackages || [],
                        handler: handlePartyPackagesUpload,
                        remover: removePartyPackages,
                        fileKey: '_partyPackagesFiles',
                    },
                ] as const).map(section => (
                    <div key={section.key} style={{ marginTop: '1.5rem' }}>
                        {/* Section Header */}
                        <div style={{
                            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                            marginBottom: '0.75rem',
                            padding: '0.5rem 0.875rem',
                            background: section.colorBg,
                            border: `1px solid ${section.colorBorder}`,
                            borderRadius: 'var(--vz-radius)',
                        }}>
                            <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: section.color, letterSpacing: '0.03em' }}>
                                {section.label}
                                <span style={{ marginLeft: '0.5rem', fontSize: '0.7rem', fontWeight: 500, color: 'var(--vz-text-muted)' }}>
                                    ({(section.files as string[]).length}/20)
                                </span>
                            </div>
                            {(section.files as string[]).length < 20 && (
                                <label style={{
                                    display: 'flex', alignItems: 'center', gap: '0.3rem',
                                    padding: '0.3rem 0.625rem',
                                    borderRadius: 'var(--vz-radius)',
                                    background: section.colorBg,
                                    color: section.color,
                                    border: `1px solid ${section.colorBorder}`,
                                    fontSize: '0.72rem', fontWeight: 600, cursor: 'pointer',
                                }}>
                                    <BiPlus /> Add Images
                                    <input
                                        type="file"
                                        accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp"
                                        multiple
                                        onChange={section.handler as any}
                                        style={{ display: 'none' }}
                                    />
                                </label>
                            )}
                        </div>

                        {/* Image Grid */}
                        {(section.files as string[]).length > 0 ? (
                            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(110px, 1fr))', gap: '0.625rem' }}>
                                {(section.files as string[]).map((url: string, idx: number) => (
                                    <div key={`${section.key}-${idx}`} style={{
                                        position: 'relative', width: '100%', paddingBottom: '141.4%',
                                        borderRadius: 'var(--vz-radius)', overflow: 'hidden',
                                        background: '#f8f9fa',
                                        border: `1.5px solid ${section.colorBorder}`,
                                    }}>
                                        <img src={url} alt={`${section.label} ${idx + 1}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
                                        <button
                                            type="button"
                                            onClick={() => (section.remover as (i: number) => void)(idx)}
                                            style={{ position: 'absolute', top: 4, right: 4, width: 22, height: 22, borderRadius: '50%', background: 'rgba(255,255,255,0.92)', color: 'var(--vz-danger)', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: '0 1px 4px rgba(0,0,0,0.15)' }}
                                        ><BiX /></button>
                                    </div>
                                ))}
                                {(section.files as string[]).length < 20 && (
                                    <label style={{
                                        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
                                        width: '100%', paddingBottom: '141.4%', position: 'relative',
                                        border: `2px dashed ${section.colorBorder}`,
                                        borderRadius: 'var(--vz-radius)', cursor: 'pointer',
                                        background: section.colorBg, transition: 'all 0.2s ease',
                                    }}>
                                        <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                                            <BiUpload style={{ fontSize: '1.25rem', color: section.color, marginBottom: '0.2rem' }} />
                                            <span style={{ fontSize: '0.625rem', fontWeight: 600, color: section.color }}>Add more</span>
                                        </div>
                                        <input type="file" accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp" multiple onChange={section.handler as any} style={{ display: 'none' }} />
                                    </label>
                                )}
                            </div>
                        ) : (
                            <label style={{
                                display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
                                padding: '1.5rem', border: `2px dashed ${section.colorBorder}`,
                                borderRadius: 'var(--vz-radius)', cursor: 'pointer',
                                background: section.colorBg, transition: 'all 0.2s ease',
                            }}>
                                <BiImage style={{ fontSize: '1.75rem', color: section.color, marginBottom: '0.4rem' }} />
                                <span style={{ fontSize: '0.8125rem', fontWeight: 600, color: section.color }}>Upload {section.label} Images</span>
                                <span style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', marginTop: '0.2rem' }}>JPG, JPEG, PNG, WEBP · Up to 20 images · Auto-compressed to 300KB</span>
                                <input type="file" accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp" multiple onChange={section.handler as any} style={{ display: 'none' }} />
                            </label>
                        )}
                    </div>
                ))}

                {/* Videos Section */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.75rem', marginTop: '1.5rem' }}>
                    <div style={{ ...sectionTitle, display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
                        <BiVideo style={{ fontSize: '1rem' }} /> Venue Videos ({form.media?.videos?.length || 0}/20)
                    </div>
                    {(form.media?.videos?.length || 0) < 20 && (
                        <label style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', padding: '0.375rem 0.75rem', borderRadius: 'var(--vz-radius)', background: 'rgba(var(--vz-primary-rgb), 0.1)', color: 'var(--vz-primary)', fontSize: '0.75rem', fontWeight: 600, cursor: 'pointer', transition: 'all 0.2s ease' }}>
                            <BiPlus /> Add Video
                            <input type="file" accept=".mp4,.mov,.avi,video/mp4,video/quicktime,video/x-msvideo" multiple onChange={handleVideosUpload} style={{ display: 'none' }} />
                        </label>
                    )}
                </div>

                {(form.media?.videos?.length || 0) > 0 ? (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '0.75rem' }}>
                        {form.media?.videos?.map((url: string, idx: number) => (
                            <div key={`vid-${idx}`} style={{ position: 'relative', width: '100%', paddingBottom: '56.25%', borderRadius: 'var(--vz-radius)', overflow: 'hidden', background: '#f8f9fa', border: '1px solid var(--vz-border-color)' }}>
                                <video src={url} controls style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
                                <button type="button" onClick={() => removeVideo(idx)} style={{ position: 'absolute', top: 4, right: 4, width: 24, height: 24, zIndex: 10, borderRadius: '50%', background: 'rgba(255,255,255,0.9)', color: 'var(--vz-danger)', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}><BiX /></button>
                            </div>
                        ))}
                        {(form.media?.videos?.length || 0) < 20 && (
                            <label style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', width: '100%', paddingBottom: '56.25%', position: 'relative', border: '2px dashed var(--vz-border-color)', borderRadius: 'var(--vz-radius)', cursor: 'pointer', background: 'var(--vz-body-bg)', transition: 'all 0.2s ease' }}>
                                <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                                    <BiUpload style={{ fontSize: '1.5rem', color: 'var(--vz-text-muted)', marginBottom: '0.25rem' }} />
                                    <span style={{ fontSize: '0.6875rem', fontWeight: 600, color: 'var(--vz-text-muted)' }}>Add video</span>
                                </div>
                                <input type="file" accept=".mp4,.mov,.avi,video/mp4,video/quicktime,video/x-msvideo" multiple onChange={handleVideosUpload} style={{ display: 'none' }} />
                            </label>
                        )}
                    </div>
                ) : (
                    <div style={{ padding: '2rem', textAlign: 'center', border: '1px dashed var(--vz-border-color)', borderRadius: 'var(--vz-radius)', background: 'var(--vz-body-bg)' }}>
                        <BiVideo style={{ fontSize: '2rem', color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }} />
                        <p style={{ margin: 0, fontSize: '0.8125rem', color: 'var(--vz-text-secondary)' }}>No videos added. Upload up to 20 promotional videos (MP4, MOV, AVI).</p>
                    </div>
                )}
                {/* Terms & Conditions — required for new venue submissions */}
                {!venue && (
                    <div style={{
                        marginTop: '2rem',
                        padding: '1.25rem',
                        background: form.termsAccepted
                            ? 'rgba(34,197,94,0.06)'
                            : 'rgba(var(--vz-warning-rgb,245,158,11),0.06)',
                        border: `1.5px solid ${
                            form.termsAccepted ? 'rgba(34,197,94,0.4)' : 'rgba(245,158,11,0.5)'
                        }`,
                        borderRadius: 'var(--vz-radius)',
                        transition: 'all 0.25s ease',
                    }}>
                        <div style={{
                            fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase',
                            letterSpacing: '0.04em', color: 'var(--vz-primary)', marginBottom: '0.75rem',
                        }}>⚖️ Legal Agreement — Required</div>

                        {/* Scrollable T&C preview */}
                        <div style={{
                            background: 'var(--vz-body-bg)',
                            border: '1px solid var(--vz-border-color)',
                            borderRadius: 'var(--vz-radius)',
                            padding: '0.875rem 1rem',
                            maxHeight: 180,
                            overflowY: 'auto',
                            fontSize: '0.75rem',
                            lineHeight: 1.75,
                            color: 'var(--vz-text-secondary)',
                            marginBottom: '1rem',
                        }}>
                            <strong style={{ color: 'var(--vz-text-primary)', display: 'block', marginBottom: '0.5rem' }}>
                                Lunara Venue Partner — Terms &amp; Conditions
                            </strong>
                            <p><strong>1. Acceptance of Terms</strong> — By accessing or using LUNARA, you agree to be bound by these Terms and Conditions and our Privacy Policy.</p>
                            <p style={{ marginTop: '0.5rem' }}><strong>2. Use of Services</strong> — You may use our services only as permitted by law. We may suspend services for non-compliance.</p>
                            <p style={{ marginTop: '0.5rem' }}><strong>3. User Accounts</strong> — You are responsible for maintaining the confidentiality of your account and password.</p>
                            <p style={{ marginTop: '0.5rem' }}><strong>4. Booking and Payments</strong> — All bookings are subject to availability. Prices are subject to change without notice.</p>
                            <p style={{ marginTop: '0.5rem' }}><strong>5. Limitation of Liability</strong> — LUNARA will not be liable for any indirect, incidental, special, or consequential damages.</p>
                            <p style={{ marginTop: '0.5rem' }}><strong>6. Changes to Terms</strong> — We may modify these terms at any time. You should look at the terms regularly.</p>
                            <p style={{ marginTop: '0.5rem', color: 'var(--vz-text-muted)', fontStyle: 'italic' }}>The complete Terms &amp; Conditions will be sent to the venue contact person's email for review and formal acceptance.</p>
                        </div>

                        {/* Acceptance checkbox */}
                        <label style={{
                            display: 'flex', alignItems: 'flex-start', gap: '0.625rem',
                            cursor: 'pointer', fontSize: '0.8125rem', color: 'var(--vz-text-primary)',
                            fontWeight: form.termsAccepted ? 600 : 400,
                        }}>
                            <input
                                type="checkbox"
                                id="venue-terms-accepted"
                                checked={form.termsAccepted}
                                onChange={e => set('termsAccepted', e.target.checked)}
                                style={{ width: 18, height: 18, marginTop: 2, accentColor: 'var(--vz-primary)', flexShrink: 0 }}
                            />
                            <span>
                                I confirm that all submitted information is accurate and I have the authority to list this venue.
                                I have read and agree to the{' '}
                                <strong>Lunara Venue Partner Terms &amp; Conditions</strong>.
                                The venue contact person will receive a confirmation email to formally accept the Terms before the venue goes live.
                            </span>
                        </label>

                        {!form.termsAccepted && (
                            <p style={{ marginTop: '0.625rem', fontSize: '0.75rem', color: '#f59e0b', display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
                                ⚠️ You must accept the Terms &amp; Conditions to submit this venue.
                            </p>
                        )}
                    </div>
                )}
            </div>
        );
    };

    const sectionTitle: React.CSSProperties = { fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '0.75rem' };

    // Close button in header — always shows confirmation if dirty
    const handleCloseRequest = () => {
        if (isFormDirty()) {
            setShowCloseConfirm(true);
        } else {
            onClose();
        }
    };

    const tabRenderers = [renderBasicInfo, renderLocation, renderContact, renderOperations, renderBusiness, renderAmenities, renderMedia];

    return (
        <div style={overlay}>
            <div className="vz-card" style={panel} onClick={e => e.stopPropagation()}>
                {/* Header */}
                <div className="vz-card-header" style={{ padding: '0.875rem 1.25rem' }}>
                    <h6 className="vz-card-title" style={{ margin: 0, fontSize: '1rem' }}>
                        {venue ? 'Edit Venue' : 'Add New Venue'}
                    </h6>
                    <button className="vz-btn-icon" onClick={handleCloseRequest}><BiX /></button>
                </div>

                {/* Tab Bar */}
                <div style={{
                    display: 'flex', gap: 0, borderBottom: '1px solid var(--vz-border-color)',
                    overflowX: 'auto', flexShrink: 0, background: 'var(--vz-card-bg)',
                }}>
                    {TAB_CONFIG.map((tab, idx) => (
                        <button
                            key={tab.key}
                            onClick={() => setActiveTab(idx)}
                            style={{
                                display: 'flex', alignItems: 'center', gap: '0.375rem',
                                padding: '0.625rem 0.875rem',
                                fontSize: '0.75rem', fontWeight: activeTab === idx ? 700 : 500,
                                color: activeTab === idx ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                                background: 'none', border: 'none',
                                borderBottom: activeTab === idx ? '2px solid var(--vz-primary)' : '2px solid transparent',
                                cursor: 'pointer', fontFamily: 'var(--vz-font)',
                                whiteSpace: 'nowrap', transition: 'all 0.2s ease',
                            }}
                        >
                            <span style={{ fontSize: '0.875rem', display: 'flex' }}>{tab.icon}</span>
                            {tab.label}
                            {/* Completion dot */}
                            {idx < activeTab && (
                                <BiCheckCircle style={{ fontSize: '0.75rem', color: 'var(--vz-success)' }} />
                            )}
                        </button>
                    ))}
                </div>

                {/* Body */}
                <div style={{ flex: 1, overflowY: 'auto', padding: '1.25rem', overflowX: 'hidden' }}>
                    {tabRenderers[activeTab]()}
                </div>

                {/* Footer */}
                <div style={{
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                    padding: '0.75rem 1.25rem', borderTop: '1px solid var(--vz-border-color)',
                    background: 'var(--vz-card-bg)', flexShrink: 0,
                }}>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                        {activeTab > 0 && (
                            <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={() => setActiveTab(prev => prev - 1)}>
                                <BiChevronLeft /> Prev
                            </button>
                        )}
                    </div>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                        Step {activeTab + 1} of {TAB_CONFIG.length}
                    </div>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                        <button type="button" className="vz-btn vz-btn-outline vz-btn-sm" onClick={handleCloseRequest}>Cancel</button>
                        {activeTab < TAB_CONFIG.length - 1 ? (
                            <button className="vz-btn vz-btn-primary vz-btn-sm" onClick={() => setActiveTab(prev => prev + 1)}>
                                Next <BiChevronRight />
                            </button>
                        ) : (
                            <button
                                className="vz-btn vz-btn-primary vz-btn-sm"
                                onClick={handleSubmit}
                                disabled={!venue && !form.termsAccepted}
                                title={!venue && !form.termsAccepted ? 'Accept the Terms & Conditions to submit' : undefined}
                                style={{
                                    opacity: (!venue && !form.termsAccepted) ? 0.45 : 1,
                                    cursor: (!venue && !form.termsAccepted) ? 'not-allowed' : 'pointer',
                                }}
                            >
                                <BiSave /> {venue ? 'Update' : 'Save'} Venue
                            </button>
                        )}
                    </div>
                </div>
            </div>

            {/* Image Crop Modal */}
            {showCropModal && (
                <ImageCropModal
                    imageSrc={cropImage}
                    onCropComplete={handleCropComplete}
                    onCancel={() => {
                        setShowCropModal(false);
                        setCropImage('');
                    }}
                    aspectRatio={16 / 9}
                />
            )}
            {/* ── Discard Changes Confirmation ────────────────────────────── */}
            {showCloseConfirm && (
                <div
                    style={{
                        position: 'fixed', inset: 0,
                        background: 'rgba(0,0,0,0.6)',
                        backdropFilter: 'blur(4px)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        zIndex: 4000,
                    }}
                    onClick={e => e.stopPropagation()}
                >
                    <div style={{
                        background: 'var(--vz-card-bg)',
                        border: '1px solid rgba(239,68,68,0.3)',
                        borderRadius: '16px',
                        padding: '2rem',
                        maxWidth: '400px',
                        width: '90%',
                        boxShadow: '0 24px 64px rgba(0,0,0,0.5)',
                        textAlign: 'center',
                    }}>
                        <div style={{
                            fontSize: '2.5rem', marginBottom: '0.75rem', lineHeight: 1,
                        }}>⚠️</div>
                        <h6 style={{ margin: '0 0 0.5rem', fontSize: '1rem', fontWeight: 700, color: 'var(--vz-text-primary)' }}>
                            Discard Changes?
                        </h6>
                        <p style={{ margin: '0 0 1.5rem', fontSize: '0.875rem', color: 'var(--vz-text-muted)' }}>
                            You have unsaved changes. If you close now, all entered data will be lost.
                        </p>
                        <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center' }}>
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                onClick={() => setShowCloseConfirm(false)}
                            >
                                Keep Editing
                            </button>
                            <button
                                className="vz-btn vz-btn-sm"
                                style={{ background: '#ef4444', color: '#fff', border: 'none' }}
                                onClick={() => { setShowCloseConfirm(false); onClose(); }}
                            >
                                Discard & Close
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default VenueForm;
