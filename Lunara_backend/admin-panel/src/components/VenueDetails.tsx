import React, { useState } from 'react';
import {
    BiX, BiStar, BiCalendar, BiGroup, BiMoney,
    BiMap, BiPhone, BiEnvelope, BiGlobe, BiLogoInstagram, BiLogoFacebookCircle,
    BiTimeFive, BiShield, BiCheck, BiChevronLeft, BiChevronRight
} from 'react-icons/bi';
import type { Venue, VenueAmenities } from '../types/venue';
import { AMENITY_CONFIG, CATEGORY_CONFIG } from '../types/venue';

interface VenueDetailsProps {
    venue: Venue;
    onClose: () => void;
}

/* ═════════ Mini Components ═════════ */

const StatCard: React.FC<{ label: string; value: string | number; icon: React.ReactNode; color: string }> = ({ label, value, icon, color }) => (
    <div style={{
        display: 'flex', alignItems: 'center', gap: '0.75rem',
        padding: '0.75rem', borderRadius: 'var(--vz-radius)',
        border: '1px solid var(--vz-border-color)',
        background: 'var(--vz-card-bg)',
    }}>
        <div style={{
            width: 38, height: 38, borderRadius: 'var(--vz-radius)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: `${color}18`, color, fontSize: '1.125rem',
        }}>{icon}</div>
        <div>
            <div style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--vz-text-primary)', lineHeight: 1.2 }}>{value}</div>
            <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>{label}</div>
        </div>
    </div>
);

const Badge: React.FC<{ label: string; color: string; bg: string }> = ({ label, color, bg }) => (
    <span style={{
        display: 'inline-block', padding: '0.1875rem 0.625rem', borderRadius: '999px',
        fontSize: '0.6875rem', fontWeight: 600, color, background: bg,
    }}>{label}</span>
);

const DetailRow: React.FC<{ icon: React.ReactNode; label: string; value?: string | number | null }> = ({ icon, label, value }) => {
    if (!value && value !== 0) return null;
    return (
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '0.625rem', marginBottom: '0.625rem' }}>
            <span style={{ fontSize: '0.875rem', color: 'var(--vz-text-muted)', marginTop: 1, flexShrink: 0, display: 'flex' }}>{icon}</span>
            <div>
                <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em' }}>{label}</div>
                <div style={{ fontSize: '0.8125rem', color: 'var(--vz-text-primary)', fontWeight: 500 }}>{value}</div>
            </div>
        </div>
    );
};

/* ═════════ STYLES ═════════ */
const overlay: React.CSSProperties = { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1080, backdropFilter: 'blur(4px)' };
const panel: React.CSSProperties = { width: '100%', maxWidth: 820, maxHeight: '92vh', display: 'flex', flexDirection: 'column', borderRadius: 'var(--vz-radius-lg)', overflow: 'hidden', boxShadow: '0 8px 40px rgba(0,0,0,0.25)' };
const sectionTitle: React.CSSProperties = { fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '0.75rem', marginTop: '1rem' };

const TABS = [
    { key: 'overview', label: 'Overview' },
    { key: 'location', label: 'Location & Contact' },
    { key: 'operations', label: 'Operations' },
    { key: 'business', label: 'Business & Compliance' },
    { key: 'amenities', label: 'Amenities' },
];

export const VenueDetails: React.FC<VenueDetailsProps> = ({ venue, onClose }) => {
    const [activeTab, setActiveTab] = useState(0);
    const [imgIdx, setImgIdx] = useState(0);
    const photos = venue.media?.photos || [];
    const catConf = CATEGORY_CONFIG[venue.category];

    const statusColors: Record<string, { color: string; bg: string }> = {
        approved: { color: 'var(--vz-success)', bg: 'rgba(var(--vz-success-rgb), 0.12)' },
        pending: { color: '#f59e0b', bg: 'rgba(245,158,11,0.12)' },
        rejected: { color: 'var(--vz-danger)', bg: 'rgba(var(--vz-danger-rgb), 0.12)' },
        suspended: { color: '#ef4444', bg: 'rgba(239,68,68,0.12)' },
    };
    const sBadge = statusColors[venue.status] || statusColors.pending;

    /* ─── Tab renderers ─── */

    const renderOverview = () => (
        <div>
            {/* Venue Header / Cover Image */}
            <div style={{ position: 'relative', width: '100%', height: 160, borderRadius: 'var(--vz-radius)', overflow: 'hidden', marginBottom: '1.25rem', background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)' }}>
                {venue.media?.coverImage ? (
                    <img src={venue.media.coverImage} alt="Cover" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                ) : (
                    <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(var(--vz-primary-rgb), 0.05)', color: 'var(--vz-text-muted)' }}>
                        No Cover Image Available
                    </div>
                )}
                <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '1.5rem 1.25rem 1rem', background: 'linear-gradient(to top, rgba(0,0,0,0.8), transparent)' }}>
                    <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
                        <div>
                            <h5 style={{ margin: 0, fontSize: '1.5rem', fontWeight: 700, color: '#fff', textShadow: '0 2px 4px rgba(0,0,0,0.5)' }}>{venue.name}</h5>
                            {venue.tagline && <p style={{ margin: '0.25rem 0 0', fontSize: '0.875rem', color: 'rgba(255,255,255,0.8)', fontStyle: 'italic', textShadow: '0 1px 2px rgba(0,0,0,0.5)' }}>{venue.tagline}</p>}
                        </div>
                        <div style={{ display: 'flex', gap: '0.375rem', flexShrink: 0 }}>
                            <Badge label={catConf.label} color={catConf.color} bg={catConf.bg} />
                            <Badge label={venue.status.charAt(0).toUpperCase() + venue.status.slice(1)} color={sBadge.color} bg={sBadge.bg} />
                        </div>
                    </div>
                </div>
            </div>

            {/* Image Gallery */}
            {photos.length > 0 && (
                <div style={{ marginBottom: '1.25rem' }}>
                    <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '0.75rem' }}>Gallery ({photos.length})</div>
                    <div style={{ position: 'relative', width: '100%', paddingBottom: '45%', borderRadius: 'var(--vz-radius)', overflow: 'hidden', background: '#1a1a1a' }}>
                        <img src={photos[imgIdx]} alt={`${venue.name} photo ${imgIdx + 1}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'contain' }} />
                        {photos.length > 1 && (
                            <>
                                <button onClick={() => setImgIdx(prev => (prev === 0 ? photos.length - 1 : prev - 1))} style={{ position: 'absolute', left: 8, top: '50%', transform: 'translateY(-50%)', width: 32, height: 32, borderRadius: '50%', border: 'none', background: 'rgba(0,0,0,0.5)', color: '#fff', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1rem' }}><BiChevronLeft /></button>
                                <button onClick={() => setImgIdx(prev => (prev === photos.length - 1 ? 0 : prev + 1))} style={{ position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)', width: 32, height: 32, borderRadius: '50%', border: 'none', background: 'rgba(0,0,0,0.5)', color: '#fff', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1rem' }}><BiChevronRight /></button>
                                <div style={{ position: 'absolute', bottom: 8, right: 10, background: 'rgba(0,0,0,0.55)', color: '#fff', padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.6875rem', fontWeight: 600 }}>{imgIdx + 1} / {photos.length}</div>
                            </>
                        )}
                    </div>
                    {/* Thumbnails */}
                    {photos.length > 1 && (
                        <div style={{ display: 'flex', gap: '0.375rem', marginTop: '0.5rem', overflowX: 'auto', paddingBottom: '0.25rem' }}>
                            {photos.map((p, i) => (
                                <img key={i} src={p} alt={`thumb-${i}`} onClick={() => setImgIdx(i)} style={{ width: 52, height: 38, objectFit: 'cover', borderRadius: 4, cursor: 'pointer', border: imgIdx === i ? '2px solid var(--vz-primary)' : '2px solid transparent', opacity: imgIdx === i ? 1 : 0.6, transition: 'all 0.2s ease', flexShrink: 0 }} />
                            ))}
                        </div>
                    )}
                </div>
            )}

            {/* Videos */}
            {venue.media?.videos && venue.media.videos.length > 0 && (
                <div style={{ marginBottom: '1.25rem' }}>
                    <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '0.75rem' }}>Videos ({venue.media.videos.length})</div>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))', gap: '0.75rem' }}>
                        {venue.media.videos.map((url, idx) => (
                            <div key={`vid-${idx}`} style={{ position: 'relative', width: '100%', paddingBottom: '56.25%', borderRadius: 'var(--vz-radius)', overflow: 'hidden', background: '#000' }}>
                                <video src={url} controls style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'contain' }} />
                            </div>
                        ))}
                    </div>
                </div>
            )}

            {/* Menus */}
            {([
                { key: 'foodMenus', label: 'Food Menu', files: venue.media?.foodMenus || [] },
                { key: 'barMenus', label: 'Bar Menu', files: venue.media?.barMenus || [] },
                { key: 'beverageMenus', label: 'Beverage Menu', files: venue.media?.beverageMenus || [] },
                { key: 'partyPackages', label: 'Party Packages', files: venue.media?.partyPackages || [] },
                { key: 'menus', label: 'Other Menus', files: venue.media?.menus || [] },
            ] as const).map(section => section.files.length > 0 && (
                <div key={section.key} style={{ marginBottom: '1.25rem' }}>
                    <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '0.75rem' }}>{section.label} ({section.files.length})</div>
                    <div style={{ display: 'flex', gap: '0.5rem', overflowX: 'auto', paddingBottom: '0.5rem' }}>
                        {section.files.map((url: string, idx: number) => (
                            <div key={`${section.key}-${idx}`} style={{ flexShrink: 0, width: 120, height: 160, borderRadius: 'var(--vz-radius)', overflow: 'hidden', background: '#1a1a1a', border: '1px solid var(--vz-border-color)' }}>
                                <img src={url} alt={`${venue.name} ${section.label} ${idx + 1}`} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                            </div>
                        ))}
                    </div>
                </div>
            ))}

            {venue.description && (
                <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-secondary)', lineHeight: 1.6, marginBottom: '1rem' }}>{venue.description}</p>
            )}

            {/* Flags */}
            <div style={{ display: 'flex', gap: '0.625rem', marginBottom: '1rem', flexWrap: 'wrap' }}>
                {venue.isVerified && <Badge label="✓ Verified" color="var(--vz-success)" bg="rgba(var(--vz-success-rgb), 0.1)" />}
                {venue.isFeatured && <Badge label="★ Featured" color="#f59e0b" bg="rgba(245,158,11,0.1)" />}
                {venue.isPremium && <Badge label="♛ Premium" color="#a855f7" bg="rgba(168,85,247,0.1)" />}
                {venue.isActive && <Badge label="● Active" color="var(--vz-success)" bg="rgba(var(--vz-success-rgb), 0.08)" />}
            </div>

            {/* Tags */}
            {venue.tags?.length > 0 && (
                <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap', marginBottom: '1rem' }}>
                    {venue.tags.map(tag => (
                        <span key={tag} style={{ padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.625rem', background: 'var(--vz-border-color)', color: 'var(--vz-text-muted)', fontWeight: 500 }}>#{tag}</span>
                    ))}
                </div>
            )}

            {/* Stats */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '0.5rem' }}>
                <StatCard label="Avg. Rating" value={`${venue.stats.averageRating} ★`} icon={<BiStar />} color="#f59e0b" />
                <StatCard label="Total Reviews" value={venue.stats.totalReviews.toLocaleString()} icon={<BiCalendar />} color="var(--vz-primary)" />
                <StatCard label="Total Bookings" value={venue.stats.totalBookings.toLocaleString()} icon={<BiGroup />} color="var(--vz-success)" />
                <StatCard label="Revenue" value={`₹${(venue.stats.totalRevenue / 100000).toFixed(1)}L`} icon={<BiMoney />} color="#a855f7" />
            </div>
        </div>
    );

    const renderLocationContact = () => (
        <div>
            <div style={sectionTitle}>Address</div>
            <DetailRow icon={<BiMap />} label="Address" value={`${venue.location.addressLine1}${venue.location.addressLine2 ? ', ' + venue.location.addressLine2 : ''}`} />
            <DetailRow icon={<BiMap />} label="Area / City" value={`${venue.location.area}, ${venue.location.city}, ${venue.location.state} — ${venue.location.pincode}`} />
            <DetailRow icon={<BiMap />} label="Country" value={venue.location.country} />
            <DetailRow icon={<BiMap />} label="Nearest Landmark" value={venue.location.nearestLandmark} />
            <DetailRow icon={<BiMap />} label="Directions" value={venue.location.directions} />
            {venue.location.latitude && venue.location.longitude && (
                <DetailRow icon={<BiGlobe />} label="Coordinates" value={`${venue.location.latitude}, ${venue.location.longitude}`} />
            )}

            <div style={sectionTitle}>Venue Contact</div>
            <DetailRow icon={<BiPhone />} label="Phone" value={venue.contact.phone} />
            <DetailRow icon={<BiPhone />} label="Mobile" value={venue.contact.mobile} />
            <DetailRow icon={<BiPhone />} label="WhatsApp" value={venue.contact.whatsapp} />
            <DetailRow icon={<BiEnvelope />} label="Email" value={venue.contact.email} />
            <DetailRow icon={<BiGlobe />} label="Website" value={venue.contact.website} />
            <DetailRow icon={<BiLogoInstagram />} label="Instagram" value={venue.contact.instagram} />
            <DetailRow icon={<BiLogoFacebookCircle />} label="Facebook" value={venue.contact.facebook} />

            <div style={sectionTitle}>Primary Contact Person</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiGroup />} label="Name" value={venue.contactPerson.name} />
                <DetailRow icon={<BiShield />} label="Designation" value={venue.contactPerson.designation} />
                <DetailRow icon={<BiPhone />} label="Mobile" value={venue.contactPerson.mobile} />
                <DetailRow icon={<BiEnvelope />} label="Email" value={venue.contactPerson.email} />
            </div>

            {venue.altContactPerson && (
                <>
                    <div style={sectionTitle}>Alternate Contact Person</div>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                        <DetailRow icon={<BiGroup />} label="Name" value={venue.altContactPerson.name} />
                        <DetailRow icon={<BiShield />} label="Designation" value={venue.altContactPerson.designation} />
                        <DetailRow icon={<BiPhone />} label="Mobile" value={venue.altContactPerson.mobile} />
                        <DetailRow icon={<BiEnvelope />} label="Email" value={venue.altContactPerson.email} />
                    </div>
                </>
            )}
        </div>
    );

    const renderOperations = () => (
        <div>
            <div style={sectionTitle}>Hours & Schedule</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiTimeFive />} label="Opening Time" value={venue.operations.openingTime} />
                <DetailRow icon={<BiTimeFive />} label="Closing Time" value={venue.operations.closingTime} />
            </div>
            <div style={{ marginBottom: '0.875rem' }}>
                <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Days Open</div>
                <div style={{ display: 'flex', gap: '0.25rem' }}>
                    {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(d => (
                        <span key={d} style={{
                            padding: '0.25rem 0.5rem', borderRadius: 'var(--vz-radius)',
                            fontSize: '0.6875rem', fontWeight: 600,
                            background: venue.operations.daysOpen?.includes(d) ? 'rgba(var(--vz-primary-rgb), 0.1)' : 'var(--vz-border-color)',
                            color: venue.operations.daysOpen?.includes(d) ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                        }}>{d}</span>
                    ))}
                </div>
            </div>
            {venue.operations.closedDates && venue.operations.closedDates.length > 0 && (
                <div style={{ marginBottom: '0.875rem' }}>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Holidays / Closed Dates</div>
                    <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                        {venue.operations.closedDates.map((d: string) => (
                            <span key={d} style={{
                                padding: '0.25rem 0.5rem', borderRadius: 'var(--vz-radius)',
                                fontSize: '0.6875rem', fontWeight: 600,
                                background: 'rgba(239,68,68,0.1)', color: '#ef4444',
                            }}>{d}</span>
                        ))}
                    </div>
                </div>
            )}

            <div style={sectionTitle}>Capacity & Pricing</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiGroup />} label="Seating" value={venue.operations.seatingCapacity} />
                <DetailRow icon={<BiGroup />} label="Standing" value={venue.operations.standingCapacity} />
                <DetailRow icon={<BiShield />} label="Age Limit" value={venue.operations.ageLimit ? `${venue.operations.ageLimit}+` : undefined} />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiMoney />} label="Cover (Male)" value={venue.operations.coverChargeMale ? `₹${venue.operations.coverChargeMale}` : 'Free'} />
                <DetailRow icon={<BiMoney />} label="Cover (Female)" value={venue.operations.coverChargeFemale ? `₹${venue.operations.coverChargeFemale}` : 'Free'} />
                <DetailRow icon={<BiMoney />} label="Discount" value={venue.operations.discountPercentage ? `${venue.operations.discountPercentage}%` : 'N/A'} />
                <DetailRow icon={<BiMoney />} label="Table Booking" value={venue.operations.tableBookingCharges ? `₹${venue.operations.tableBookingCharges}` : 'N/A'} />
                <DetailRow icon={<BiMoney />} label="Couple Entry Fee" value={venue.operations.coupleEntryFee ? `₹${venue.operations.coupleEntryFee}` : 'N/A'} />
            </div>
            <DetailRow icon={<BiShield />} label="Dress Code" value={venue.operations.dressCode} />

            {venue.operations.cuisineTypes?.length > 0 && (
                <div style={{ marginBottom: '0.875rem' }}>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Cuisine Types</div>
                    <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                        {venue.operations.cuisineTypes.map(c => (
                            <span key={c} style={{ padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.625rem', background: 'rgba(var(--vz-primary-rgb), 0.08)', color: 'var(--vz-primary)', fontWeight: 500 }}>{c}</span>
                        ))}
                    </div>
                </div>
            )}

            {venue.operations.musicTypes?.length > 0 && (
                <div>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Music Types</div>
                    <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                        {venue.operations.musicTypes.map(m => (
                            <span key={m} style={{ padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.625rem', background: 'rgba(var(--vz-success-rgb), 0.08)', color: 'var(--vz-success)', fontWeight: 500 }}>{m}</span>
                        ))}
                    </div>
                </div>
            )}
        </div>
    );

    const renderBusiness = () => (
        <div>
            <div style={sectionTitle}>Tax & Registration</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiShield />} label="PAN Number" value={venue.business.panNumber} />
                <DetailRow icon={<BiShield />} label="GST Number" value={venue.business.gstNumber} />
            </div>

            <div style={sectionTitle}>Licenses & Certificates</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiCheck />} label="FSSAI License" value={venue.business.fssaiLicense} />
                <DetailRow icon={<BiCheck />} label="Liquor License" value={venue.business.liquorLicense} />
                <DetailRow icon={<BiCheck />} label="Fire Safety Cert" value={venue.business.fireSafetyCert} />
                <DetailRow icon={<BiCheck />} label="Trade License" value={venue.business.tradeLicense} />
            </div>

            <div style={sectionTitle}>Bank Details</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiMoney />} label="Bank Name" value={venue.business.bankName} />
                <DetailRow icon={<BiMoney />} label="Account No." value={venue.business.bankAccountNumber} />
                <DetailRow icon={<BiMoney />} label="IFSC Code" value={venue.business.bankIFSC} />
            </div>

            <div style={sectionTitle}>Metadata</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiCalendar />} label="Owner" value={venue.ownerName} />
                <DetailRow icon={<BiCalendar />} label="Owner ID" value={venue.ownerId} />
                <DetailRow icon={<BiCalendar />} label="Created" value={new Date(venue.createdAt).toLocaleDateString('en-IN', { dateStyle: 'long' })} />
                <DetailRow icon={<BiCalendar />} label="Last Updated" value={new Date(venue.updatedAt).toLocaleDateString('en-IN', { dateStyle: 'long' })} />
            </div>
        </div>
    );

    const renderAmenities = () => (
        <div>
            <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)', marginBottom: '1rem' }}>
                Amenities available at <strong>{venue.name}</strong>
            </p>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                {(Object.keys(AMENITY_CONFIG) as (keyof VenueAmenities)[]).map(key => {
                    const available = venue.amenities[key];
                    return (
                        <div key={key} style={{
                            display: 'flex', alignItems: 'center', gap: '0.625rem',
                            padding: '0.625rem 0.875rem', borderRadius: 'var(--vz-radius)',
                            border: `1.5px solid ${available ? 'var(--vz-success)' : 'var(--vz-border-color)'}`,
                            background: available ? 'rgba(var(--vz-success-rgb), 0.04)' : 'transparent',
                            opacity: available ? 1 : 0.5,
                        }}>
                            <span style={{ fontSize: '1.125rem' }}>{AMENITY_CONFIG[key].icon}</span>
                            <span style={{ fontSize: '0.8125rem', fontWeight: available ? 600 : 400, color: available ? 'var(--vz-text-primary)' : 'var(--vz-text-muted)' }}>
                                {AMENITY_CONFIG[key].label}
                            </span>
                            <span style={{ marginLeft: 'auto', fontSize: '0.8125rem' }}>
                                {available ? <BiCheck style={{ color: 'var(--vz-success)' }} /> : '—'}
                            </span>
                        </div>
                    );
                })}
            </div>
        </div>
    );

    const tabRenderers = [renderOverview, renderLocationContact, renderOperations, renderBusiness, renderAmenities];

    return (
        <div style={overlay} onClick={onClose}>
            <div className="vz-card" style={panel} onClick={e => e.stopPropagation()}>
                {/* Header */}
                <div className="vz-card-header" style={{ padding: '0.875rem 1.25rem' }}>
                    <h6 className="vz-card-title" style={{ margin: 0, fontSize: '1rem' }}>Venue Details</h6>
                    <button className="vz-btn-icon" onClick={onClose}><BiX /></button>
                </div>

                {/* Tab Bar */}
                <div style={{
                    display: 'flex', gap: 0, borderBottom: '1px solid var(--vz-border-color)',
                    overflowX: 'auto', flexShrink: 0, background: 'var(--vz-card-bg)',
                }}>
                    {TABS.map((tab, idx) => (
                        <button
                            key={tab.key}
                            onClick={() => setActiveTab(idx)}
                            style={{
                                padding: '0.625rem 1rem',
                                fontSize: '0.75rem', fontWeight: activeTab === idx ? 700 : 500,
                                color: activeTab === idx ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                                background: 'none', border: 'none',
                                borderBottom: activeTab === idx ? '2px solid var(--vz-primary)' : '2px solid transparent',
                                cursor: 'pointer', fontFamily: 'var(--vz-font)',
                                whiteSpace: 'nowrap', transition: 'all 0.2s ease',
                            }}
                        >{tab.label}</button>
                    ))}
                </div>

                {/* Body */}
                <div style={{ flex: 1, overflowY: 'auto', padding: '1.25rem', overflowX: 'hidden' }}>
                    {tabRenderers[activeTab]()}
                </div>

                {/* Footer */}
                <div style={{
                    display: 'flex', justifyContent: 'flex-end',
                    padding: '0.75rem 1.25rem', borderTop: '1px solid var(--vz-border-color)',
                    background: 'var(--vz-card-bg)', flexShrink: 0,
                }}>
                    <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={onClose}>Close</button>
                </div>
            </div>
        </div>
    );
};

export default VenueDetails;
