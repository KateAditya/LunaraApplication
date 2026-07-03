import { useState, useEffect } from 'react';
import { BiSearch, BiPlus, BiEdit, BiTrash, BiRefresh } from 'react-icons/bi';
import toast from 'react-hot-toast';
import { type Ad, adsApi } from '../api/ads';
import AdForm from '../components/AdForm';
import { format } from 'date-fns';

const getImageUrl = (filePath?: string): string => {
    if (!filePath) return '';
    if (filePath.startsWith('http')) return filePath;
    const normalizedPath = filePath.replace(/\\/g, '/');
    const baseUrl = import.meta.env.VITE_API_URL || 'http://localhost:5000';
    return `${baseUrl}/${normalizedPath}`;
};

export default function Ads() {
    const [ads, setAds] = useState<Ad[]>([]);
    const [loading, setLoading] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');
    const [isFormOpen, setIsFormOpen] = useState(false);
    const [selectedAd, setSelectedAd] = useState<Ad | null>(null);

    const fetchAds = async () => {
        setLoading(true);
        try {
            const res = await adsApi.getAds();
            if (res.success) {
                setAds(res.data);
            } else {
                toast.error('Failed to load ads');
            }
        } catch (error) {
            console.error('Error fetching ads:', error);
            toast.error('Failed to load ads');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchAds();
    }, []);

    const handleEdit = (ad: Ad) => {
        setSelectedAd(ad);
        setIsFormOpen(true);
    };

    const handleDelete = async (id: string) => {
        if (!window.confirm('Are you sure you want to delete this ad?')) return;
        try {
            const res = await adsApi.deleteAd(id);
            if (res.success) {
                toast.success('Ad deleted successfully');
                fetchAds();
            } else {
                toast.error(res.message || 'Failed to delete ad');
            }
        } catch (error) {
            console.error('Error deleting ad:', error);
            toast.error('Error deleting ad');
        }
    };

    const handleFormSuccess = () => {
        setIsFormOpen(false);
        fetchAds();
    };

    const handleFormClose = () => {
        setIsFormOpen(false);
        setSelectedAd(null);
    };

    const filteredAds = ads.filter((ad) => {
        const query = searchQuery.toLowerCase();
        return (
            (ad.city || '').toLowerCase().includes(query) ||
            (ad.area || '').toLowerCase().includes(query) ||
            (ad.venue?.name || '').toLowerCase().includes(query)
        );
    });


    return (
        <div style={{ paddingBottom: '80px' }}>
            {/* Toolbar */}
            <div className="vz-card mb-3 animate-in animate-in-5">
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '0.75rem' }}>
                        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
                            <div style={{ position: 'relative' }}>
                                <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                                <input
                                    className="vz-form-control"
                                    placeholder="Search by city, area, or venue..."
                                    value={searchQuery}
                                    onChange={(e) => setSearchQuery(e.target.value)}
                                    style={{ paddingLeft: '2.25rem', width: 250 }}
                                />
                            </div>
                            <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={fetchAds} title="Refresh" disabled={loading}>
                                <BiRefresh style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
                            </button>
                        </div>
                        <button className="vz-btn vz-btn-primary" onClick={() => { setSelectedAd(null); setIsFormOpen(true); }}>
                            <BiPlus /> Add Ad
                        </button>
                    </div>
                </div>
            </div>

            {/* Ad Table */}
            <div className="vz-card animate-in animate-in-6">
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {loading && (
                        <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>
                            <div className="spinner-border spinner-border-sm" role="status" style={{ marginRight: '0.5rem' }} />
                            Loading ads...
                        </div>
                    )}
                    
                    {!loading && (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr>
                                        <th>Image</th>
                                        <th>Location</th>
                                        <th>Venue</th>
                                        <th>Validity</th>
                                        <th>Status</th>
                                        <th style={{ width: 110 }}>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {filteredAds.length === 0 ? (
                                        <tr>
                                            <td colSpan={6} style={{ textAlign: 'center', padding: '2rem', color: 'var(--vz-text-muted)' }}>
                                                No ads found. {searchQuery && 'Try a different search term.'}
                                            </td>
                                        </tr>
                                    ) : (
                                        filteredAds.map((ad) => (
                                            <tr key={ad.id}>
                                                <td style={{ verticalAlign: 'middle' }}>
                                                    <img
                                                        src={getImageUrl(ad.imagePath)}
                                                        alt="Ad Banner"
                                                        style={{ width: 100, height: 50, objectFit: 'cover', borderRadius: '4px', border: '1px solid var(--vz-border-color)' }}
                                                    />
                                                </td>
                                                <td>
                                                    <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>{ad.city}</div>
                                                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>{ad.area}</div>
                                                </td>
                                                <td>
                                                    <span style={{
                                                        display: 'inline-block',
                                                        padding: '0.2rem 0.5rem',
                                                        borderRadius: '4px',
                                                        fontSize: '0.6875rem',
                                                        fontWeight: 600,
                                                        color: 'var(--vz-primary)',
                                                        background: 'rgba(var(--vz-primary-rgb), 0.1)',
                                                    }}>
                                                        {ad.venue?.name || 'Unknown Venue'}
                                                    </span>
                                                </td>
                                                <td>
                                                    <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', whiteSpace: 'nowrap' }}>
                                                        <span style={{ fontWeight: 500 }}>From:</span> {format(new Date(ad.fromDate), 'dd MMM yyyy')}
                                                    </div>
                                                    <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', whiteSpace: 'nowrap' }}>
                                                        <span style={{ fontWeight: 500 }}>To:</span> {format(new Date(ad.toDate), 'dd MMM yyyy')}
                                                    </div>
                                                </td>
                                                <td>
                                                    <span className={`vz-badge ${ad.isActive ? 'success' : 'secondary'}`}>
                                                        {ad.isActive ? 'Active' : 'Inactive'}
                                                    </span>
                                                </td>
                                                <td>
                                                    <div style={{ display: 'flex', gap: '0.25rem' }}>
                                                        <button className="vz-btn-icon" title="Edit" onClick={() => handleEdit(ad)}><BiEdit /></button>
                                                        <button className="vz-btn-icon" title="Delete" style={{ color: 'var(--vz-danger)' }} onClick={() => handleDelete(ad.id)}><BiTrash /></button>
                                                    </div>
                                                </td>
                                            </tr>
                                        ))
                                    )}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>

            {/* Ad Form Modal */}
            {isFormOpen && (
                <div style={{
                    position: 'fixed', inset: 0,
                    background: 'rgba(0,0,0,0.6)',
                    backdropFilter: 'blur(4px)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    zIndex: 2000,
                }}>
                    <div style={{ width: '100%', maxWidth: '800px', height: '90vh' }}>
                        <AdForm
                            ad={selectedAd}
                            onClose={handleFormClose}
                            onSuccess={handleFormSuccess}
                        />
                    </div>
                </div>
            )}
        </div>
    );
}
