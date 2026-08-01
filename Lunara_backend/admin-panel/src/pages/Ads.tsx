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
    const [activeTab, setActiveTab] = useState<'all' | 'Ads' | 'Party'>('Ads');
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
        const adType = ad.type || 'Ads';
        if (activeTab !== 'all' && adType !== activeTab) {
            return false;
        }
        const query = searchQuery.toLowerCase();
        return (
            (ad.title || '').toLowerCase().includes(query) ||
            (ad.city || '').toLowerCase().includes(query) ||
            (ad.area || '').toLowerCase().includes(query) ||
            (ad.venue?.name || '').toLowerCase().includes(query)
        );
    });

    const adsCount = ads.filter((a) => (a.type || 'Ads') === 'Ads').length;
    const partyCount = ads.filter((a) => a.type === 'Party').length;

    return (
        <div style={{ paddingBottom: '80px' }}>
            {/* Tabs Header */}
            <div className="vz-card mb-3 animate-in animate-in-4" style={{ borderRadius: '12px' }}>
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ display: 'flex', gap: '0.75rem', borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.5rem' }}>
                        {[
                            { key: 'Ads', label: '📢 General Ads', count: adsCount },
                            { key: 'Party', label: '🎉 Party Ads', count: partyCount },
                            { key: 'all', label: '📋 All Banners', count: ads.length },
                        ].map((tab) => {
                            const isActive = activeTab === tab.key;
                            return (
                                <button
                                    key={tab.key}
                                    onClick={() => setActiveTab(tab.key as any)}
                                    style={{
                                        padding: '0.5rem 1rem',
                                        borderRadius: '8px',
                                        border: 'none',
                                        background: isActive ? 'rgba(124, 58, 237, 0.12)' : 'transparent',
                                        cursor: 'pointer',
                                        fontSize: '0.875rem',
                                        fontWeight: isActive ? 700 : 500,
                                        color: isActive ? '#7c3aed' : 'var(--vz-text-muted)',
                                        borderBottom: isActive ? '3px solid #7c3aed' : '3px solid transparent',
                                        display: 'flex',
                                        alignItems: 'center',
                                        gap: '0.5rem',
                                        transition: 'all 0.2s ease',
                                    }}
                                >
                                    <span>{tab.label}</span>
                                    <span
                                        style={{
                                            padding: '0.15rem 0.5rem',
                                            borderRadius: '12px',
                                            fontSize: '0.75rem',
                                            fontWeight: 700,
                                            background: isActive ? '#7c3aed' : 'var(--vz-light)',
                                            color: isActive ? '#ffffff' : 'var(--vz-text-muted)',
                                        }}
                                    >
                                        {tab.count}
                                    </span>
                                </button>
                            );
                        })}
                    </div>
                </div>
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
                                    placeholder="Search by title, city, area, venue..."
                                    value={searchQuery}
                                    onChange={(e) => setSearchQuery(e.target.value)}
                                    style={{ paddingLeft: '2.25rem', width: 280 }}
                                />
                            </div>
                            <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={fetchAds} title="Refresh" disabled={loading}>
                                <BiRefresh style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
                            </button>
                        </div>
                        <button className="vz-btn vz-btn-primary" onClick={() => { setSelectedAd(null); setIsFormOpen(true); }}>
                            <BiPlus /> {activeTab === 'Party' ? 'Add Party Ad' : 'Add General Ad'}
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
                                        <th>Type</th>
                                        <th>Title & Location</th>
                                        <th>Venue</th>
                                        <th>Validity</th>
                                        <th>Status</th>
                                        <th style={{ width: 110 }}>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {filteredAds.length === 0 ? (
                                        <tr>
                                            <td colSpan={7} style={{ textAlign: 'center', padding: '2.5rem', color: 'var(--vz-text-muted)' }}>
                                                No {activeTab === 'all' ? 'ads' : activeTab === 'Party' ? 'Party Ads' : 'General Ads'} found. {searchQuery && 'Try a different search query.'}
                                            </td>
                                        </tr>
                                    ) : (
                                        filteredAds.map((ad) => {
                                            const isParty = ad.type === 'Party';
                                            return (
                                                <tr key={ad.id}>
                                                    <td style={{ verticalAlign: 'middle' }}>
                                                        <img
                                                            src={getImageUrl(ad.imagePath)}
                                                            alt="Ad Banner"
                                                            style={{ width: 100, height: 50, objectFit: 'cover', borderRadius: '6px', border: '1px solid var(--vz-border-color)' }}
                                                        />
                                                    </td>
                                                    <td style={{ verticalAlign: 'middle' }}>
                                                        <span
                                                            style={{
                                                                padding: '0.25rem 0.6rem',
                                                                borderRadius: '6px',
                                                                fontSize: '0.75rem',
                                                                fontWeight: 700,
                                                                color: isParty ? '#7c3aed' : '#2563eb',
                                                                background: isParty ? 'rgba(124, 58, 237, 0.12)' : 'rgba(37, 99, 235, 0.12)',
                                                                border: isParty ? '1px solid rgba(124, 58, 237, 0.3)' : '1px solid rgba(37, 99, 235, 0.3)',
                                                                display: 'inline-block',
                                                                whiteSpace: 'nowrap',
                                                            }}
                                                        >
                                                            {isParty ? '🎉 Party' : '📢 General Ad'}
                                                        </span>
                                                    </td>
                                                    <td>
                                                        {ad.title && (
                                                            <div style={{ fontWeight: 700, fontSize: '0.8125rem', color: 'var(--vz-text-primary)', marginBottom: '2px' }}>
                                                                {ad.title}
                                                            </div>
                                                        )}
                                                        <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>{ad.city || 'All Cities'}</div>
                                                        {ad.area && <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>{ad.area}</div>}
                                                    </td>
                                                    <td>
                                                        <span style={{
                                                            display: 'inline-block',
                                                            padding: '0.2rem 0.5rem',
                                                            borderRadius: '4px',
                                                            fontSize: '0.6875rem',
                                                            fontWeight: 600,
                                                            color: isParty ? '#7c3aed' : 'var(--vz-primary)',
                                                            background: isParty ? 'rgba(124, 58, 237, 0.1)' : 'rgba(var(--vz-primary-rgb), 0.1)',
                                                        }}>
                                                            {ad.venue?.name || 'General App Ad'}
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
                                            );
                                        })
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
                            defaultType={activeTab === 'Party' ? 'Party' : 'Ads'}
                            onClose={handleFormClose}
                            onSuccess={handleFormSuccess}
                        />
                    </div>
                </div>
            )}
        </div>
    );
}
