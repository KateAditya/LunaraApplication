import React, { useState, useEffect } from 'react';
import { getImageUrl } from '../utils/imageUrl';
import { BiX, BiUpload, BiTrash, BiPlus, BiCheck } from 'react-icons/bi';
import toast from 'react-hot-toast';
import { type Ad, adsApi, type SocialLink } from '../api/ads';
import { venuesApi, type Venue } from '../api/venues';
import { format } from 'date-fns';

import { compressImageIfNeeded } from '../utils/mediaValidation';

interface AdFormProps {
    ad: Ad | null;
    defaultType?: 'Ads' | 'Party';
    onClose: () => void;
    onSuccess: () => void;
}

export default function AdForm({ ad, defaultType = 'Ads', onClose, onSuccess }: AdFormProps) {
    const [loading, setLoading] = useState(false);
    const [venues, setVenues] = useState<Venue[]>([]);

    // Form State
    const [type, setType] = useState<'Ads' | 'Party'>(ad?.type || defaultType || 'Ads');
    const [city, setCity] = useState(ad?.city || '');
    const [area, setArea] = useState(ad?.area || '');
    const [venueId, setVenueId] = useState(ad?.venueId || '');
    const [title, setTitle] = useState(ad?.title || '');
    const [aboutEvent, setAboutEvent] = useState(ad?.aboutEvent || '');

    // YYYY-MM-DD formatting for date inputs
    const [fromDate, setFromDate] = useState(ad?.fromDate ? format(new Date(ad.fromDate), 'yyyy-MM-dd') : '');
    const [toDate, setToDate] = useState(ad?.toDate ? format(new Date(ad.toDate), 'yyyy-MM-dd') : '');

    const [isActive, setIsActive] = useState(ad ? ad.isActive : true);
    const [imageFile, setImageFile] = useState<File | null>(null);
    const [imagePreview, setImagePreview] = useState<string | null>(ad?.imagePath ? getImageUrl(ad.imagePath) : null);
    const [socialLinks, setSocialLinks] = useState<SocialLink[]>(ad?.socialLinks || []);

    // Derived lists for dropdowns
    const uniqueCities = Array.from(new Set(venues.map(v => v.city))).filter(Boolean);
    const uniqueAreas = Array.from(new Set(venues.filter(v => v.city === city).map(v => v.area || ''))).filter(Boolean);
    const availableVenues = venues.filter(v => v.city === city && (v.area || '') === area);

    useEffect(() => {
        const loadVenues = async () => {
            try {
                const res = await venuesApi.getVenues();
                if (res.success) {
                    setVenues(res.venues);
                }
            } catch (error) {
                toast.error('Failed to load venues data');
            }
        };
        loadVenues();
    }, []);

    // Handle cascading resets
    useEffect(() => {
        if (!ad) {
            setArea('');
            setVenueId('');
        }
    }, [city, ad]);

    useEffect(() => {
        if (!ad) {
            setVenueId('');
        }
    }, [area, ad]);



    const handleImageChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        // Basic validation
        const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/avif'];
        if (!validTypes.includes(file.type)) {
            toast.error('Invalid file type. Please upload JPG, PNG, WEBP, or AVIF.');
            return;
        }

        try {
            const compressed = await compressImageIfNeeded(file, 300);
            setImageFile(compressed);
            setImagePreview(URL.createObjectURL(compressed));
        } catch (error) {
            toast.error('Failed to process image');
        }
    };

    const handleAddLink = () => {
        setSocialLinks([...socialLinks, { platform: 'Instagram', url: '' }]);
    };

    const handleUpdateLink = (index: number, field: keyof SocialLink, value: string) => {
        const newLinks = [...socialLinks];
        newLinks[index][field] = value;
        setSocialLinks(newLinks);
    };

    const handleRemoveLink = (index: number) => {
        const newLinks = socialLinks.filter((_, i) => i !== index);
        setSocialLinks(newLinks);
    };

    const validateForm = () => {
        if (!type) { toast.error('Please select a Type'); return false; }
        if (type === 'Party') {
            if (!city) { toast.error('Please select a City'); return false; }
            if (!area) { toast.error('Please select an Area'); return false; }
            if (!venueId) { toast.error('Please select a Venue'); return false; }
        }
        if (!fromDate) { toast.error('Please select From Date'); return false; }
        if (!toDate) { toast.error('Please select To Date'); return false; }
        if (!ad && !imageFile) { toast.error('Please upload an image'); return false; }

        if (new Date(fromDate) > new Date(toDate)) {
            toast.error('From Date cannot be later than To Date');
            return false;
        }

        // Validate URLs
        for (const link of socialLinks) {
            if (!link.platform.trim()) { toast.error('Platform name cannot be empty'); return false; }
            if (!link.url.trim()) { toast.error('URL cannot be empty'); return false; }
            try {
                new URL(link.url);
            } catch (_) {
                toast.error(`Invalid URL for platform: ${link.platform}`);
                return false;
            }
        }

        return true;
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!validateForm()) return;

        setLoading(true);
        try {
            const formData = new FormData();
            formData.append('type', type);
            if (city) formData.append('city', city);
            if (area) formData.append('area', area);
            if (title) formData.append('title', title);
            if (venueId) formData.append('venueId', venueId);
            formData.append('aboutEvent', aboutEvent);
            formData.append('fromDate', fromDate);
            formData.append('toDate', toDate);
            formData.append('isActive', isActive.toString());
            formData.append('socialLinks', JSON.stringify(socialLinks));

            if (imageFile) {
                formData.append('image', imageFile);
            }

            let res;
            if (ad) {
                res = await adsApi.updateAd(ad.id, formData);
            } else {
                res = await adsApi.createAd(formData);
            }

            if (res.success) {
                toast.success(ad ? 'Ad updated successfully' : 'Ad created successfully');
                onSuccess();
            } else {
                toast.error((res as any).message || 'Failed to save ad');
            }
        } catch (error: any) {
            console.error('Error saving ad:', error);
            const errorMsg = error.response?.data?.message || error.message || 'Failed to save ad';
            toast.error(errorMsg);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--vz-body-bg)', overflow: 'hidden', borderRadius: '16px' }}>
            <div style={{
                padding: '1rem 1.25rem', borderBottom: '1px solid var(--vz-border-color)',
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                background: 'var(--vz-card-bg)', flexShrink: 0
            }}>
                <h2 style={{ margin: 0, fontSize: '1.125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>
                    {ad ? 'Edit Advertisement' : 'Create New Advertisement'}
                </h2>
                <button
                    onClick={onClose}
                    style={{ background: 'transparent', border: 'none', color: 'var(--vz-text-muted)', cursor: 'pointer', fontSize: '1.5rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                >
                    <BiX />
                </button>
            </div>

            <div style={{ flex: 1, overflowY: 'auto', padding: '1.25rem', background: 'var(--vz-body-bg)' }}>
                <form id="ad-form" onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>

                    {/* Location Section */}
                    <div className="vz-card" style={{ marginBottom: 0 }}>
                        <div className="vz-card-body">
                            <h5 style={{ margin: '0 0 1rem', fontSize: '1rem', color: 'var(--vz-text-primary)', borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.5rem' }}>Target Location</h5>
                            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '1rem' }}>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>Type <span style={{ color: 'var(--vz-danger)' }}>*</span></label>
                                    <select
                                        value={type}
                                        onChange={(e) => setType(e.target.value as 'Ads' | 'Party')}
                                        className="vz-form-control"
                                        required
                                    >
                                        <option value="Ads">Ads</option>
                                        <option value="Party">Party</option>
                                    </select>
                                </div>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>City {type === 'Party' && <span style={{ color: 'var(--vz-danger)' }}>*</span>}</label>
                                    <select
                                        value={city}
                                        onChange={(e) => setCity(e.target.value)}
                                        className="vz-form-control"
                                        required={type === 'Party'}
                                    >
                                        <option value="">Select City</option>
                                        {uniqueCities.map(c => (
                                            <option key={c} value={c}>{c}</option>
                                        ))}
                                    </select>
                                </div>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>Area {type === 'Party' && <span style={{ color: 'var(--vz-danger)' }}>*</span>}</label>
                                    <select
                                        value={area}
                                        onChange={(e) => setArea(e.target.value)}
                                        className="vz-form-control"
                                        disabled={!city}
                                        required={type === 'Party'}
                                    >
                                        <option value="">Select Area</option>
                                        {uniqueAreas.map(a => (
                                            <option key={a} value={a}>{a}</option>
                                        ))}
                                    </select>
                                </div>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>Venue {type === 'Party' && <span style={{ color: 'var(--vz-danger)' }}>*</span>}</label>
                                    <select
                                        value={venueId}
                                        onChange={(e) => setVenueId(e.target.value)}
                                        className="vz-form-control"
                                        disabled={!area}
                                        required={type === 'Party'}
                                    >
                                        <option value="">Select Venue</option>
                                        {availableVenues.map(v => (
                                            <option key={v.id} value={v.id}>{v.name}</option>
                                        ))}
                                    </select>
                                </div>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>Title {type === 'Party' && <span style={{ color: 'var(--vz-danger)' }}>*</span>}</label>
                                    <input
                                        type="text"
                                        value={title}
                                        onChange={(e) => setTitle(e.target.value)}
                                        className="vz-form-control"
                                        placeholder="Enter Title"
                                        required={type === 'Party'}
                                    />
                                </div>
                            </div>

                            {type === 'Party' && (
                                <div style={{ marginTop: '1.25rem' }}>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>About this event (Optional)</label>
                                    <textarea
                                        value={aboutEvent}
                                        onChange={(e) => setAboutEvent(e.target.value)}
                                        className="vz-form-control"
                                        rows={3}
                                        placeholder="Join us for an unforgettable night..."
                                    />
                                </div>
                            )}
                        </div>
                    </div>

                    {/* Banner Settings */}
                    <div className="vz-card" style={{ marginBottom: 0 }}>
                        <div className="vz-card-body">
                            <h5 style={{ margin: '0 0 1rem', fontSize: '1rem', color: 'var(--vz-text-primary)', borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.5rem' }}>Banner Settings</h5>
                            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '1rem', marginBottom: '1.25rem' }}>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>From Date <span style={{ color: 'var(--vz-danger)' }}>*</span></label>
                                    <input
                                        type="date"
                                        value={fromDate}
                                        onChange={(e) => setFromDate(e.target.value)}
                                        className="vz-form-control"
                                        required
                                    />
                                </div>
                                <div>
                                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>To Date <span style={{ color: 'var(--vz-danger)' }}>*</span></label>
                                    <input
                                        type="date"
                                        value={toDate}
                                        onChange={(e) => setToDate(e.target.value)}
                                        className="vz-form-control"
                                        required
                                    />
                                </div>
                            </div>

                            <div style={{ marginBottom: '1.25rem' }}>
                                <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>Banner Image <span style={{ color: 'var(--vz-danger)' }}>*</span></label>
                                <div style={{ display: 'flex', alignItems: 'flex-start', gap: '1.5rem' }}>
                                    <div style={{ flex: 1 }}>
                                        <label style={{
                                            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
                                            width: '100%', height: '120px', border: '2px dashed var(--vz-border-color)', borderRadius: '8px',
                                            cursor: 'pointer', background: 'var(--vz-body-bg)', transition: 'border-color 0.2s'
                                        }}>
                                            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '1rem' }}>
                                                <BiUpload style={{ fontSize: '2rem', color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }} />
                                                <p style={{ margin: 0, fontSize: '0.875rem', color: 'var(--vz-text-muted)' }}><span style={{ fontWeight: 600, color: 'var(--vz-primary)' }}>Click to upload</span> or drag and drop</p>
                                                <p style={{ margin: '0.25rem 0 0', fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>JPG, PNG, WEBP, AVIF (Auto-compresses to 300KB)</p>
                                            </div>
                                            <input type="file" style={{ display: 'none' }} accept="image/jpeg,image/png,image/webp,image/avif" onChange={handleImageChange} />
                                        </label>
                                    </div>
                                    {imagePreview && (
                                        <div style={{ width: '180px', height: '120px', borderRadius: '8px', overflow: 'hidden', border: '1px solid var(--vz-border-color)', flexShrink: 0 }}>
                                            <img src={imagePreview} alt="Preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                        </div>
                                    )}
                                </div>
                            </div>

                            <div>
                                <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', cursor: 'pointer', fontSize: '0.875rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>
                                    <input
                                        type="checkbox"
                                        checked={isActive}
                                        onChange={(e) => setIsActive(e.target.checked)}
                                        style={{ width: '16px', height: '16px', cursor: 'pointer' }}
                                    />
                                    Activate this Ad
                                </label>
                            </div>
                        </div>
                    </div>

                    {/* Social Media Links */}
                    <div className="vz-card" style={{ marginBottom: 0 }}>
                        <div className="vz-card-body">
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem', borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.5rem' }}>
                                <h5 style={{ margin: 0, fontSize: '1rem', color: 'var(--vz-text-primary)' }}>Action Links</h5>
                                <button
                                    type="button"
                                    onClick={handleAddLink}
                                    style={{ background: 'none', border: 'none', color: 'var(--vz-primary)', fontSize: '0.8125rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.25rem', cursor: 'pointer' }}
                                >
                                    <BiPlus /> Add Link
                                </button>
                            </div>

                            {socialLinks.length === 0 ? (
                                <div style={{ textAlign: 'center', padding: '1.5rem', color: 'var(--vz-text-muted)', fontSize: '0.875rem', background: 'var(--vz-body-bg)', borderRadius: '8px', border: '1px dashed var(--vz-border-color)' }}>
                                    No links added. Click 'Add Link' to attach social media or website URLs.
                                </div>
                            ) : (
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                                    {socialLinks.map((link, idx) => (
                                        <div key={idx} style={{ display: 'flex', gap: '0.75rem', alignItems: 'flex-start' }}>
                                            <div style={{ flex: '0 0 30%' }}>
                                                <input
                                                    type="text"
                                                    placeholder="Platform (e.g. Instagram)"
                                                    value={link.platform}
                                                    onChange={(e) => handleUpdateLink(idx, 'platform', e.target.value)}
                                                    className="vz-form-control"
                                                />
                                            </div>
                                            <div style={{ flex: 1 }}>
                                                <input
                                                    type="url"
                                                    placeholder="https://..."
                                                    value={link.url}
                                                    onChange={(e) => handleUpdateLink(idx, 'url', e.target.value)}
                                                    className="vz-form-control"
                                                />
                                            </div>
                                            <button
                                                type="button"
                                                onClick={() => handleRemoveLink(idx)}
                                                className="vz-btn-icon"
                                                style={{ color: 'var(--vz-danger)', padding: '0.5rem', flexShrink: 0 }}
                                            >
                                                <BiTrash />
                                            </button>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                </form>
            </div>

            <div style={{
                display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: '0.5rem',
                padding: '0.75rem 1.25rem', borderTop: '1px solid var(--vz-border-color)',
                background: 'var(--vz-card-bg)', flexShrink: 0
            }}>
                <button
                    type="button"
                    onClick={onClose}
                    className="vz-btn vz-btn-outline vz-btn-sm"
                >
                    Cancel
                </button>
                <button
                    type="submit"
                    form="ad-form"
                    disabled={loading}
                    className="vz-btn vz-btn-primary vz-btn-sm"
                    style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}
                >
                    {loading ? (
                        <div className="spinner-border spinner-border-sm" role="status" style={{ marginRight: '0.25rem' }} />
                    ) : (
                        <BiCheck />
                    )}
                    {ad ? 'Update Ad' : 'Publish Ad'}
                </button>
            </div>
        </div>
    );
}
