import React, { useState, useEffect, useCallback } from 'react';
import { BiSearch, BiPlus, BiEdit, BiTrash, BiShow, BiMapPin, BiStar, BiRefresh } from 'react-icons/bi';
import { CATEGORY_CONFIG } from '../types/venue';
import { VenueForm } from '../components/VenueForm';
import { VenueDetails } from '../components/VenueDetails';
import toast from 'react-hot-toast';
import apiClient from '../api/client';

// ── DB Venue shape (flat, as returned by the server) ───────────────────────────
interface DbVenue {
    id: string;
    name: string;
    slug: string;
    tagline?: string;
    description?: string;
    category: string;
    tags?: string[];
    addressLine1: string;
    addressLine2?: string;
    area?: string;
    city: string;
    state: string;
    postalCode: string;
    country?: string;
    latitude?: number;
    longitude?: number;
    nearestLandmark?: string;
    directions?: string;
    phone: string;
    mobile?: string;
    whatsapp?: string;
    email?: string;
    website?: string;
    instagram?: string;
    facebook?: string;
    cpName?: string;
    cpDesignation?: string;
    cpMobile?: string;
    cpEmail?: string;
    altCpName?: string;
    altCpDesignation?: string;
    altCpMobile?: string;
    altCpEmail?: string;
    capacity: number;
    seatingCapacity?: number;
    standingCapacity?: number;
    openingTime?: string;
    closingTime?: string;
    daysOpen?: string[];
    ageLimit?: number;
    coverChargeMale?: number;
    coverChargeFemale?: number;
    discountPercentage?: number;
    tableBookingCharges?: number;
    coupleEntryFee?: number;
    dressCode?: string;
    cuisineTypes?: string[];
    musicTypes?: string[];
    amenities?: any;
    panNumber?: string;
    gstNumber?: string;
    fssaiLicense?: string;
    liquorLicense?: string;
    fireSafetyCert?: string;
    tradeLicense?: string;
    bankAccountNumber?: string;
    bankIFSC?: string;
    bankName?: string;
    averageRating: number;
    totalReviews: number;
    status: string;
    featured: boolean;
    isActive: boolean;
    isPremium: boolean;
    isVerified?: boolean;
    displayOrder?: number;
    createdAt: string;
    updatedAt: string;
    ownerId: string;
    images?: any[];
}

const getImageUrl = (filePath?: string): string => {
    if (!filePath) return '';
    if (filePath.startsWith('http')) return filePath;
    const normalizedPath = filePath.replace(/\\/g, '/');
    const baseUrl = import.meta.env.VITE_API_URL || 'http://localhost:5000';
    return `${baseUrl}/${normalizedPath}`;
};

const toRichVenue = (v: DbVenue) => {
    const coverImageObj = (v as any).coverImage;
    const photoObjs = (v as any).gallery || [];
    const videoObjs = (v as any).videos || [];
    // The backend groups menus under `v.menu` object with arrays for each type.
    const menuObj = (v as any).menu || {};
    const foodMenuObjs = menuObj.foodMenu || [];
    const barMenuObjs = menuObj.barMenu || [];
    const beverageMenuObjs = menuObj.beverageMenu || [];
    const partyPackagesObjs = menuObj.partyPackages || [];
    // Note: 'menus' was legacy, backend doesn't explicitly group legacy menus, 
    // but if it did it would be in menu.menu or something. Let's just handle specific menus.
    const menuObjs = (v as any).images?.filter((img: any) => img.imageType === 'menu') || [];

    return {
        id: v.id,
        name: v.name,
        tagline: v.tagline || '',
        description: v.description || '',
        category: v.category as any,
        tags: v.tags || [],
        status: v.status as any,
        isActive: v.isActive ?? true,
        isVerified: v.isVerified ?? false,
        isFeatured: v.featured,
        isPremium: v.isPremium ?? false,
        createdAt: v.createdAt,
        updatedAt: v.updatedAt,
        ownerId: v.ownerId,
        ownerName: '',
        displayOrder: v.displayOrder || 0,
        location: {
            addressLine1: v.addressLine1,
            addressLine2: v.addressLine2 || '',
            area: v.area || '',
            city: v.city,
            state: v.state,
            pincode: v.postalCode,
            country: v.country || 'India',
            latitude: v.latitude || 0,
            longitude: v.longitude || 0,
            nearestLandmark: v.nearestLandmark || '',
            directions: v.directions || '',
        },
        contact: {
            phone: v.phone,
            mobile: v.mobile || v.phone,
            email: v.email || '',
            whatsapp: v.whatsapp || '',
            website: v.website || '',
            instagram: v.instagram || '',
            facebook: v.facebook || '',
        },
        contactPerson: {
            name: v.cpName || '',
            designation: v.cpDesignation || '',
            mobile: v.cpMobile || '',
            email: v.cpEmail || '',
        },
        altContactPerson: {
            name: v.altCpName || '',
            designation: v.altCpDesignation || '',
            mobile: v.altCpMobile || '',
            email: v.altCpEmail || '',
        },
        business: {
            panNumber: v.panNumber || '',
            gstNumber: v.gstNumber || '',
            fssaiLicense: v.fssaiLicense || '',
            liquorLicense: v.liquorLicense || '',
            fireSafetyCert: v.fireSafetyCert || '',
            tradeLicense: v.tradeLicense || '',
            bankAccountNumber: v.bankAccountNumber || '',
            bankIFSC: v.bankIFSC || '',
            bankName: v.bankName || '',
        },
        operations: {
            openingTime: v.openingTime || '',
            closingTime: v.closingTime || '',
            daysOpen: v.daysOpen || [],
            seatingCapacity: v.seatingCapacity ?? v.capacity,
            standingCapacity: v.standingCapacity,
            cuisineTypes: v.cuisineTypes || [],
            musicTypes: v.musicTypes || [],
            ageLimit: v.ageLimit ?? 21,
            coverChargeMale: v.coverChargeMale,
            coverChargeFemale: v.coverChargeFemale,
            discountPercentage: v.discountPercentage,
            tableBookingCharges: v.tableBookingCharges,
            coupleEntryFee: v.coupleEntryFee,
            dressCode: v.dressCode || '',
        },
        amenities: v.amenities || {},
        media: {
            coverImage: getImageUrl(coverImageObj?.filePath),
            photos: photoObjs.map((img: any) => getImageUrl(img.filePath)),
            videos: videoObjs.map((img: any) => getImageUrl(img.filePath)),
            menus: menuObjs.map((img: any) => getImageUrl(img.filePath)),
            foodMenus: foodMenuObjs.map((img: any) => getImageUrl(img.filePath)),
            barMenus: barMenuObjs.map((img: any) => getImageUrl(img.filePath)),
            beverageMenus: beverageMenuObjs.map((img: any) => getImageUrl(img.filePath)),
            partyPackages: partyPackagesObjs.map((img: any) => getImageUrl(img.filePath)),
        },
        stats: {
            averageRating: v.averageRating,
            totalReviews: v.totalReviews,
            totalBookings: 0,
            monthlyBookings: 0,
            totalRevenue: 0,
        },
    };
};

const getStatusBadge = (status: string) => {
    const map: Record<string, string> = {
        approved: 'success',
        live: 'success',
        suspended: 'warning',
        pending: 'info',
        submitted: 'info',
        pending_confirmation: 'warning',
        rejected: 'danger',
        draft: 'secondary',
    };
    return map[status?.toLowerCase()] || 'secondary';
};

const getStatusLabel = (status: string) => {
    const map: Record<string, string> = {
        approved: 'Approved',
        live: '🟢 Live',
        suspended: 'Suspended',
        pending: 'Pending',
        submitted: 'Submitted',
        pending_confirmation: '📧 Awaiting Owner',
        rejected: 'Rejected',
        draft: 'Draft',
    };
    return map[status?.toLowerCase()] || status;
};

export const Venues: React.FC = () => {
    // ── Data state ──────────────────────────────────────────────────────────────
    const [venues, setVenues] = useState<DbVenue[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // ── Filter / pagination ─────────────────────────────────────────────────────
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState('all');
    const [typeFilter, setTypeFilter] = useState('all');
    const [currentPage, setCurrentPage] = useState(1);
    const perPage = 10;

    // ── Modal state ─────────────────────────────────────────────────────────────
    const [showForm, setShowForm] = useState(false);
    const [showDetails, setShowDetails] = useState(false);
    const [selectedVenue, setSelectedVenue] = useState<any>(null);
    const [saving, setSaving] = useState(false);
    const [deleteTarget, setDeleteTarget] = useState<DbVenue | null>(null);
    const [deleting, setDeleting] = useState(false);

    // ── Fetch venues from API ───────────────────────────────────────────────────
    const fetchVenues = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const res: any = await apiClient.get('/api/venues');
            // The controller returns { success, venues } or { success, data: { venues } }
            const list: DbVenue[] = res?.venues || res?.data?.venues || res?.data || [];
            setVenues(Array.isArray(list) ? list : []);
        } catch (err: any) {
            const msg = err?.response?.data?.message || err?.message || 'Failed to load venues';
            setError(msg);
            toast.error(msg);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => { fetchVenues(); }, [fetchVenues]);

    // ── CRUD handlers ───────────────────────────────────────────────────────────
    const handleView = (v: DbVenue) => { setSelectedVenue(toRichVenue(v)); setShowDetails(true); };
    const handleAdd = () => { setSelectedVenue(null); setShowForm(true); };
    const handleEdit = (v: DbVenue) => { setSelectedVenue(toRichVenue(v)); setShowForm(true); };

    const handleDelete = (v: DbVenue) => {
        setDeleteTarget(v);
    };

    const confirmDelete = async () => {
        if (!deleteTarget) return;
        setDeleting(true);
        const toastId = toast.loading(`Deleting "${deleteTarget.name}"...`);
        try {
            await apiClient.delete(`/api/venues/${deleteTarget.id}`);
            toast.success(`"${deleteTarget.name}" deleted successfully`, { id: toastId });
            setVenues(prev => prev.filter(x => x.id !== deleteTarget.id));
            setDeleteTarget(null);
        } catch (err: any) {
            const msg = err?.response?.data?.message || err?.message || 'Delete failed';
            toast.error(msg, { id: toastId });
        } finally {
            setDeleting(false);
        }
    };

    const handleSave = async (data: any) => {
        setSaving(true);
        const toastId = toast.loading(selectedVenue ? 'Updating venue...' : 'Creating venue...');
        try {
            const fd = new FormData();
            const skip = new Set(['_coverFile', '_photoFiles', '_videoFiles', '_menuFiles', '_foodMenuFiles', '_barMenuFiles', '_beverageMenuFiles', '_partyPackagesFiles', 'media', 'amenities', 'daysOpen', 'cuisineTypes', 'musicTypes']);
            for (const [key, value] of Object.entries(data)) {
                if (skip.has(key)) continue;
                if (value !== null && value !== undefined) fd.append(key, String(value));
            }
            fd.append('amenities', JSON.stringify(data.amenities ?? {}));
            fd.append('daysOpen', JSON.stringify(data.daysOpen ?? []));
            fd.append('cuisineTypes', JSON.stringify(data.cuisineTypes ?? []));
            fd.append('musicTypes', JSON.stringify(data.musicTypes ?? []));
            // T&C acceptance — required for new venue creation
            if (!selectedVenue?.id) {
                fd.append('termsAccepted', String(data.termsAccepted ?? false));
            }
            if (data.media) {
                const filterBlob = (urls: any) => {
                    if (!Array.isArray(urls)) return [];
                    return urls.filter(url => typeof url === 'string' && !url.startsWith('blob:'));
                };
                fd.append('keepCoverImage', String(!!data.media.coverImage && !data.media.coverImage.startsWith('blob:')));
                fd.append('keepPhotos', JSON.stringify(filterBlob(data.media.photos)));
                fd.append('keepVideos', JSON.stringify(filterBlob(data.media.videos)));
                fd.append('keepMenus', JSON.stringify(filterBlob(data.media.menus)));
                fd.append('keepFoodMenus', JSON.stringify(filterBlob(data.media.foodMenus)));
                fd.append('keepBarMenus', JSON.stringify(filterBlob(data.media.barMenus)));
                fd.append('keepBeverageMenus', JSON.stringify(filterBlob(data.media.beverageMenus)));
                fd.append('keepPartyPackages', JSON.stringify(filterBlob(data.media.partyPackages)));
            }
            if (data._coverFile instanceof File) fd.append('coverImage', data._coverFile, data._coverFile.name);
            if (Array.isArray(data._photoFiles)) {
                for (const file of data._photoFiles) {
                    if (file instanceof File) fd.append('photos', file, file.name);
                }
            }
            if (Array.isArray(data._videoFiles)) {
                for (const file of data._videoFiles) {
                    if (file instanceof File) fd.append('videos', file, file.name);
                }
            }
            if (Array.isArray(data._menuFiles)) {
                for (const file of data._menuFiles) {
                    if (file instanceof File) fd.append('menus', file, file.name);
                }
            }
            if (Array.isArray(data._foodMenuFiles)) {
                for (const file of data._foodMenuFiles) {
                    if (file instanceof File) fd.append('foodMenus', file, file.name);
                }
            }
            if (Array.isArray(data._barMenuFiles)) {
                for (const file of data._barMenuFiles) {
                    if (file instanceof File) fd.append('barMenus', file, file.name);
                }
            }
            if (Array.isArray(data._beverageMenuFiles)) {
                for (const file of data._beverageMenuFiles) {
                    if (file instanceof File) fd.append('beverageMenus', file, file.name);
                }
            }
            if (Array.isArray(data._partyPackagesFiles)) {
                for (const file of data._partyPackagesFiles) {
                    if (file instanceof File) fd.append('partyPackages', file, file.name);
                }
            }

            if (selectedVenue?.id) {
                // apiClient interceptor already unwraps response.data, so the return
                // value is the parsed JSON body: { success, venue }
                const response: any = await apiClient.put(`/api/venues/${selectedVenue.id}`, fd);
                toast.success('Venue updated successfully', { id: toastId });
                // Refresh from server to pick up any server-side transforms (slug, optimized image paths, etc.)
                if (response?.success && response?.venue) {
                    setSelectedVenue(toRichVenue(response.venue));
                }
            } else {
                await apiClient.post('/api/venues', fd);
                toast.success('Venue created successfully', { id: toastId });
            }

            setShowForm(false);
            setSelectedVenue(null);
            fetchVenues(); // Refresh list from server
        } catch (err: any) {
            const msg = err?.response?.data?.message || err?.message || 'Failed to save venue';
            toast.error(msg, { id: toastId });
        } finally {
            setSaving(false);
        }
    };

    // ── Filtering ───────────────────────────────────────────────────────────────
    const filtered = venues.filter(v => {
        const matchSearch = !search ||
            v.name?.toLowerCase().includes(search.toLowerCase()) ||
            v.city?.toLowerCase().includes(search.toLowerCase()) ||
            v.addressLine1?.toLowerCase().includes(search.toLowerCase());
        const matchStatus = statusFilter === 'all' || v.status?.toLowerCase() === statusFilter;
        const matchType = typeFilter === 'all' || v.category?.toLowerCase() === typeFilter;
        return matchSearch && matchStatus && matchType;
    });
    const totalPages = Math.ceil(filtered.length / perPage);
    const paged = filtered.slice((currentPage - 1) * perPage, currentPage * perPage);

    // ── Summary counts ──────────────────────────────────────────────────────────
    const approved = venues.filter(v => v.status === 'approved' || v.status === 'live').length;
    const pending = venues.filter(v => v.status === 'pending' || v.status === 'submitted').length;
    const awaitingOwner = venues.filter(v => v.status === 'pending_confirmation').length;
    const suspended = venues.filter(v => v.status === 'suspended').length;
    const rejected = venues.filter(v => v.status === 'rejected').length;

    return (
        <div style={{ paddingBottom: '80px' }}>
            {/* Summary Cards */}
            <div className="row g-3 mb-4">
                {[
                    { label: 'Total Venues', value: venues.length, cls: 'primary' },
                    { label: 'Live / Approved', value: approved, cls: 'success' },
                    { label: 'Awaiting Owner', value: awaitingOwner, cls: 'warning' },
                    { label: 'Pending Review', value: pending, cls: 'info' },
                    { label: 'Suspended / Rejected', value: suspended + rejected, cls: 'danger' },
                ].map((s, i) => (
                    <div className="col-sm-6 col-xl-3" key={s.label}>
                        <div className={`stat-card animate-in animate-in-${i + 1}`}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <div>
                                    <div className="stat-card-label">{s.label}</div>
                                    <div className="stat-card-value">
                                        {loading ? '—' : s.value}
                                    </div>
                                </div>
                                <div className={`stat-card-icon ${s.cls}`} />
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Toolbar */}
            <div className="vz-card mb-3 animate-in animate-in-5">
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '0.75rem' }}>
                        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
                            <div style={{ position: 'relative' }}>
                                <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                                <input
                                    className="vz-form-control"
                                    placeholder="Search venues..."
                                    value={search}
                                    onChange={(e) => { setSearch(e.target.value); setCurrentPage(1); }}
                                    style={{ paddingLeft: '2.25rem', width: 220 }}
                                />
                            </div>
                            <select
                                className="vz-form-control"
                                value={typeFilter}
                                onChange={(e) => { setTypeFilter(e.target.value); setCurrentPage(1); }}
                                style={{ width: 130 }}
                            >
                                <option value="all">All Types</option>
                                <option value="club">Club</option>
                                <option value="pub">Pub</option>
                                <option value="bar">Bar</option>
                                <option value="lounge">Lounge</option>
                                <option value="cafe">Cafe</option>
                                <option value="restaurant">Restaurant</option>
                                <option value="rooftop">Rooftop</option>
                                <option value="hotel">Hotel</option>
                            </select>
                            <select
                                className="vz-form-control"
                                value={statusFilter}
                                onChange={(e) => { setStatusFilter(e.target.value); setCurrentPage(1); }}
                                style={{ width: 130 }}
                            >
                                <option value="all">All Status</option>
                                <option value="live">Live</option>
                                <option value="approved">Approved</option>
                                <option value="pending_confirmation">Awaiting Owner</option>
                                <option value="submitted">Submitted</option>
                                <option value="pending">Pending Review</option>
                                <option value="draft">Draft</option>
                                <option value="suspended">Suspended</option>
                                <option value="rejected">Rejected</option>
                            </select>
                            <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={fetchVenues} title="Refresh" disabled={loading}>
                                <BiRefresh style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
                            </button>
                        </div>
                        <button className="vz-btn vz-btn-primary" onClick={handleAdd}>
                            <BiPlus /> Add Venue
                        </button>
                    </div>
                </div>
            </div>

            {/* Table */}
            <div className="vz-card animate-in animate-in-6">
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {/* Loading state */}
                    {loading && (
                        <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>
                            <div className="spinner-border spinner-border-sm" role="status" style={{ marginRight: '0.5rem' }} />
                            Loading venues from database...
                        </div>
                    )}

                    {/* Error state */}
                    {!loading && error && (
                        <div style={{ textAlign: 'center', padding: '3rem' }}>
                            <div style={{ color: 'var(--vz-danger)', marginBottom: '1rem' }}>{error}</div>
                            <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={fetchVenues}>Retry</button>
                        </div>
                    )}

                    {/* Data table */}
                    {!loading && !error && (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr>
                                        <th style={{ width: 50 }}>#</th>
                                        <th>Venue</th>
                                        <th>Type</th>
                                        <th>Location</th>
                                        <th>Rating</th>
                                        <th>Capacity</th>
                                        <th>Status</th>
                                        <th style={{ width: 110 }}>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {paged.length === 0 ? (
                                        <tr>
                                            <td colSpan={8} style={{ textAlign: 'center', padding: '2rem', color: 'var(--vz-text-muted)' }}>
                                                {venues.length === 0 ? 'No venues found in database. Click "Add Venue" to create one.' : 'No venues match your search.'}
                                            </td>
                                        </tr>
                                    ) : (
                                        paged.map((venue, idx) => {
                                            const catConfig = CATEGORY_CONFIG[venue.category as keyof typeof CATEGORY_CONFIG];
                                            return (
                                                <tr key={venue.id}>
                                                    <td style={{ color: 'var(--vz-text-muted)' }}>
                                                        {(currentPage - 1) * perPage + idx + 1}
                                                    </td>
                                                    <td>
                                                        <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>{venue.name}</div>
                                                        <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                                                            {venue.description?.slice(0, 60) || venue.slug}
                                                        </div>
                                                    </td>
                                                    <td>
                                                        <span style={{
                                                            display: 'inline-block',
                                                            padding: '0.2rem 0.5rem',
                                                            borderRadius: '4px',
                                                            fontSize: '0.6875rem',
                                                            fontWeight: 600,
                                                            color: catConfig?.color || 'var(--vz-text-muted)',
                                                            background: catConfig?.bg || 'rgba(128,128,128,0.1)',
                                                            textTransform: 'capitalize',
                                                        }}>
                                                            {catConfig?.label || venue.category}
                                                        </span>
                                                    </td>
                                                    <td>
                                                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', color: 'var(--vz-text-muted)' }}>
                                                            <BiMapPin style={{ fontSize: '0.875rem' }} />
                                                            {venue.city}{venue.state ? `, ${venue.state}` : ''}
                                                        </div>
                                                    </td>
                                                    <td>
                                                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                                                            <BiStar style={{ color: '#f5b849', fontSize: '0.875rem' }} />
                                                            <span style={{ fontWeight: 600 }}>{venue.averageRating ? Number(venue.averageRating).toFixed(1) : '0.0'}</span>
                                                            <span style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                                                                ({venue.totalReviews || 0})
                                                            </span>
                                                        </div>
                                                    </td>
                                                    <td style={{ color: 'var(--vz-text-muted)' }}>
                                                        {venue.capacity || '—'}
                                                    </td>
                                                    <td>
                                                        <span className={`vz-badge ${getStatusBadge(venue.status)}`}>
                                                            {getStatusLabel(venue.status)}
                                                        </span>
                                                    </td>
                                                    <td>
                                                        <div style={{ display: 'flex', gap: '0.25rem' }}>
                                                            <button className="vz-btn-icon" title="View" onClick={() => handleView(venue)}><BiShow /></button>
                                                            <button className="vz-btn-icon" title="Edit" onClick={() => handleEdit(venue)}><BiEdit /></button>
                                                            <button className="vz-btn-icon" title="Delete" style={{ color: 'var(--vz-danger)' }} onClick={() => handleDelete(venue)}><BiTrash /></button>
                                                        </div>
                                                    </td>
                                                </tr>
                                            );
                                        })
                                    )}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>

                {/* Pagination */}
                {!loading && !error && totalPages > 1 && (
                    <div style={{
                        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                        padding: '0.75rem 1.25rem', borderTop: '1px solid var(--vz-border-color)',
                    }}>
                        <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                            Showing {(currentPage - 1) * perPage + 1}–{Math.min(currentPage * perPage, filtered.length)} of {filtered.length}
                        </span>
                        <div style={{ display: 'flex', gap: '0.25rem' }}>
                            <button className="vz-btn vz-btn-outline vz-btn-sm" disabled={currentPage === 1} onClick={() => setCurrentPage(p => p - 1)}>Prev</button>
                            {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => i + 1).map(p => (
                                <button key={p} className={`vz-btn vz-btn-sm ${p === currentPage ? 'vz-btn-primary' : 'vz-btn-outline'}`} onClick={() => setCurrentPage(p)}>{p}</button>
                            ))}
                            <button className="vz-btn vz-btn-outline vz-btn-sm" disabled={currentPage === totalPages} onClick={() => setCurrentPage(p => p + 1)}>Next</button>
                        </div>
                    </div>
                )}
            </div>

            {/* CRUD Modals */}
            {showForm && (
                <VenueForm
                    venue={selectedVenue}
                    onClose={() => { setShowForm(false); setSelectedVenue(null); }}
                    onSave={handleSave}
                />
            )}
            {showDetails && selectedVenue && (
                <VenueDetails
                    venue={selectedVenue}
                    onClose={() => { setShowDetails(false); setSelectedVenue(null); }}
                />
            )}

            {/* ── Delete Confirmation Modal ─────────────────────────────────── */}
            {deleteTarget && (
                <div style={{
                    position: 'fixed', inset: 0,
                    background: 'rgba(0,0,0,0.55)',
                    backdropFilter: 'blur(4px)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    zIndex: 3000,
                }}>
                    <div style={{
                        background: 'var(--vz-card-bg)',
                        border: '1px solid rgba(239,68,68,0.3)',
                        borderRadius: '16px',
                        padding: '2rem',
                        maxWidth: '440px',
                        width: '90%',
                        boxShadow: '0 24px 64px rgba(0,0,0,0.5)',
                        animation: 'fadeInScale 0.18s ease',
                    }}>
                        {/* Icon */}
                        <div style={{ textAlign: 'center', marginBottom: '1.25rem' }}>
                            <div style={{
                                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                                width: 56, height: 56,
                                borderRadius: '50%',
                                background: 'rgba(239,68,68,0.12)',
                                border: '2px solid rgba(239,68,68,0.3)',
                                fontSize: '1.5rem',
                            }}>
                                🗑️
                            </div>
                        </div>

                        {/* Title */}
                        <h3 style={{
                            textAlign: 'center',
                            fontSize: '1.125rem',
                            fontWeight: 700,
                            color: 'var(--vz-text-primary)',
                            marginBottom: '0.5rem',
                        }}>
                            Delete Venue
                        </h3>

                        {/* Body */}
                        <p style={{
                            textAlign: 'center',
                            fontSize: '0.875rem',
                            color: 'var(--vz-text-muted)',
                            lineHeight: 1.6,
                            marginBottom: '0.5rem',
                        }}>
                            Are you sure you want to permanently delete
                        </p>
                        <p style={{
                            textAlign: 'center',
                            fontWeight: 700,
                            fontSize: '1rem',
                            color: '#ef4444',
                            marginBottom: '0.75rem',
                        }}>
                            &ldquo;{deleteTarget.name}&rdquo;
                        </p>
                        <p style={{
                            textAlign: 'center',
                            fontSize: '0.75rem',
                            color: 'var(--vz-text-muted)',
                            marginBottom: '1.75rem',
                        }}>
                            This will also delete all photos, videos, and compliance records.
                            <br /><strong style={{ color: '#ef4444' }}>This action cannot be undone.</strong>
                        </p>

                        {/* Buttons */}
                        <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center' }}>
                            <button
                                className="vz-btn vz-btn-outline"
                                style={{ minWidth: 120 }}
                                disabled={deleting}
                                onClick={() => setDeleteTarget(null)}
                            >
                                Cancel
                            </button>
                            <button
                                className="vz-btn"
                                style={{
                                    minWidth: 140,
                                    background: 'linear-gradient(135deg,#dc2626,#ef4444)',
                                    color: '#fff',
                                    border: 'none',
                                    opacity: deleting ? 0.7 : 1,
                                }}
                                disabled={deleting}
                                onClick={confirmDelete}
                            >
                                {deleting ? 'Deleting...' : '🗑️ Yes, Delete'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
            {saving && (
                <div style={{
                    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.3)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    zIndex: 2000, backdropFilter: 'blur(2px)',
                }}>
                    <div style={{ background: 'var(--vz-card-bg)', borderRadius: '12px', padding: '1.5rem 2.5rem', textAlign: 'center' }}>
                        <div className="spinner-border" role="status" style={{ color: 'var(--vz-primary)' }} />
                        <div style={{ marginTop: '0.75rem', color: 'var(--vz-text-primary)', fontWeight: 600 }}>Saving...</div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default Venues;
