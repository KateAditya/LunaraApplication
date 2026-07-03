import React, { useState, useEffect, useCallback } from 'react';
import { BiPlus, BiEdit, BiTrash, BiSearch, BiX, BiCheckCircle, BiError, BiShield } from 'react-icons/bi';
import toast from 'react-hot-toast';
import { communityGuidelinesApi } from '../api/supportLegal';
import type { CommunityGuideline } from '../api/supportLegal';

const CATEGORIES = ['Behavior', 'Content', 'Privacy', 'Safety', 'Venue Rules', 'Community Standards', 'Other'];

const emptyForm = { title: '', content: '', category: 'Behavior', isActive: true, displayOrder: 0 };

export const CommunityGuidelines: React.FC = () => {
    const [guidelines, setGuidelines] = useState<CommunityGuideline[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [filterCat, setFilterCat] = useState('');
    const [showModal, setShowModal] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState({ ...emptyForm });
    const [saving, setSaving] = useState(false);
    const [deleteTarget, setDeleteTarget] = useState<CommunityGuideline | null>(null);
    const [deleting, setDeleting] = useState(false);
    const [formErrors, setFormErrors] = useState<Record<string, string>>({});

    const fetchGuidelines = useCallback(async () => {
        setLoading(true);
        try {
            const res = await communityGuidelinesApi.getAll();
            setGuidelines(res.guidelines || []);
        } catch { toast.error('Failed to load community guidelines'); }
        finally { setLoading(false); }
    }, []);

    useEffect(() => { fetchGuidelines(); }, [fetchGuidelines]);

    const openAdd = () => { setForm({ ...emptyForm }); setFormErrors({}); setEditingId(null); setShowModal(true); };
    const openEdit = (g: CommunityGuideline) => {
        setForm({ title: g.title, content: g.content, category: g.category, isActive: g.isActive, displayOrder: g.displayOrder });
        setFormErrors({}); setEditingId(g.id); setShowModal(true);
    };
    const closeModal = () => { setShowModal(false); setEditingId(null); };

    const validate = () => {
        const e: Record<string, string> = {};
        if (!form.title.trim()) e.title = 'Title is required';
        if (!form.content.trim()) e.content = 'Content is required';
        if (!form.category) e.category = 'Category is required';
        setFormErrors(e);
        return Object.keys(e).length === 0;
    };

    const handleSave = async () => {
        if (!validate()) return;
        setSaving(true);
        try {
            if (editingId) { await communityGuidelinesApi.update(editingId, form); toast.success('Guideline updated'); }
            else { await communityGuidelinesApi.create(form); toast.success('Guideline created'); }
            closeModal(); fetchGuidelines();
        } catch (err: any) {
            toast.error(err?.response?.data?.message || 'Failed to save guideline');
        } finally { setSaving(false); }
    };

    const handleDelete = async () => {
        if (!deleteTarget) return;
        setDeleting(true);
        try {
            await communityGuidelinesApi.delete(deleteTarget.id);
            toast.success('Guideline deleted'); setDeleteTarget(null); fetchGuidelines();
        } catch { toast.error('Failed to delete guideline'); }
        finally { setDeleting(false); }
    };

    const filtered = guidelines.filter(g =>
        (!search || g.title.toLowerCase().includes(search.toLowerCase()) || g.category.toLowerCase().includes(search.toLowerCase())) &&
        (!filterCat || g.category === filterCat)
    );

    const stats = [
        { label: 'Total Guidelines', value: guidelines.length, icon: <BiShield />, cls: 'primary' },
        { label: 'Active', value: guidelines.filter(g => g.isActive).length, icon: <BiCheckCircle />, cls: 'success' },
        { label: 'Inactive', value: guidelines.filter(g => !g.isActive).length, icon: <BiError />, cls: 'warning' },
        { label: 'Categories', value: [...new Set(guidelines.map(g => g.category))].length, icon: <BiShield />, cls: 'info' },
    ];

    return (
        <div>
            <div className="row g-3 mb-4">
                {stats.map((s, i) => (
                    <div className="col-sm-6 col-xl-3" key={s.label}>
                        <div className={`stat-card animate-in animate-in-${i + 1}`}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                <div><div className="stat-card-label">{s.label}</div><div className="stat-card-value">{s.value}</div></div>
                                <div className={`stat-card-icon ${s.cls}`}>{s.icon}</div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            <div className="vz-card animate-in animate-in-5">
                <div className="vz-card-header">
                    <h6 className="vz-card-title">Community Guidelines</h6>
                    <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
                        <div style={{ position: 'relative' }}>
                            <BiSearch style={{ position: 'absolute', left: 8, top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)', fontSize: '0.875rem' }} />
                            <input id="cg-search" className="vz-form-control" style={{ paddingLeft: '1.75rem', width: 200 }} placeholder="Search guidelines..." value={search} onChange={e => setSearch(e.target.value)} />
                        </div>
                        <select id="cg-filter-cat" className="vz-form-select" style={{ width: 'auto' }} value={filterCat} onChange={e => setFilterCat(e.target.value)}>
                            <option value="">All Categories</option>
                            {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
                        </select>
                        <button id="cg-add-btn" className="vz-btn vz-btn-primary vz-btn-sm" onClick={openAdd}><BiPlus /> Add Guideline</button>
                    </div>
                </div>
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {loading ? (
                        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>Loading...</div>
                    ) : filtered.length === 0 ? (
                        <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <BiShield style={{ fontSize: '2.5rem', display: 'block', margin: '0 auto 0.5rem' }} />
                            No guidelines found.{!search && !filterCat && <> <span style={{ cursor: 'pointer', color: 'var(--vz-primary)' }} onClick={openAdd}>Add the first one.</span></>}
                        </div>
                    ) : (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr><th>Title</th><th>Category</th><th>Status</th><th>Order</th><th>Created</th><th style={{ textAlign: 'right' }}>Actions</th></tr>
                                </thead>
                                <tbody>
                                    {filtered.map(g => (
                                        <tr key={g.id}>
                                            <td style={{ fontWeight: 500, maxWidth: 260 }}><div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{g.title}</div></td>
                                            <td><span className="vz-badge info">{g.category}</span></td>
                                            <td><span className={`vz-badge ${g.isActive ? 'success' : 'secondary'}`}>{g.isActive ? 'Active' : 'Inactive'}</span></td>
                                            <td style={{ color: 'var(--vz-text-muted)' }}>{g.displayOrder}</td>
                                            <td style={{ color: 'var(--vz-text-muted)', fontSize: '0.75rem' }}>{new Date(g.createdAt).toLocaleDateString()}</td>
                                            <td style={{ textAlign: 'right' }}>
                                                <div style={{ display: 'flex', gap: '0.25rem', justifyContent: 'flex-end' }}>
                                                    <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={() => openEdit(g)} title="Edit"><BiEdit /></button>
                                                    <button className="vz-btn vz-btn-sm" style={{ background: 'rgba(230,83,60,0.1)', color: '#e6533c', border: '1px solid rgba(230,83,60,0.2)' }} onClick={() => setDeleteTarget(g)} title="Delete"><BiTrash /></button>
                                                </div>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>

            {/* Add/Edit Modal */}
            {showModal && (
                <div style={{ position: 'fixed', inset: 0, zIndex: 1050, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }} onClick={e => { if (e.target === e.currentTarget) closeModal(); }}>
                    <div style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 12, width: '100%', maxWidth: 620, maxHeight: '90vh', overflow: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '1.25rem 1.5rem', borderBottom: '1px solid var(--vz-border-color)' }}>
                            <h6 style={{ margin: 0, fontWeight: 600, color: 'var(--vz-text-primary)' }}>{editingId ? 'Edit Guideline' : 'Add Guideline'}</h6>
                            <button onClick={closeModal} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--vz-text-muted)', fontSize: '1.25rem' }}><BiX /></button>
                        </div>
                        <div style={{ padding: '1.5rem', display: 'grid', gap: '1rem' }}>
                            <div>
                                <label className="vz-form-label" htmlFor="cg-title">Title <span style={{ color: '#e6533c' }}>*</span></label>
                                <input id="cg-title" className="vz-form-control" placeholder="Enter guideline title" value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))} />
                                {formErrors.title && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.title}</div>}
                            </div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>
                                <div>
                                    <label className="vz-form-label" htmlFor="cg-category">Category <span style={{ color: '#e6533c' }}>*</span></label>
                                    <select id="cg-category" className="vz-form-select" value={form.category} onChange={e => setForm(f => ({ ...f, category: e.target.value }))}>
                                        {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
                                    </select>
                                    {formErrors.category && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.category}</div>}
                                </div>
                                <div>
                                    <label className="vz-form-label" htmlFor="cg-order">Display Order</label>
                                    <input id="cg-order" type="number" className="vz-form-control" placeholder="0" min={0} value={form.displayOrder} onChange={e => setForm(f => ({ ...f, displayOrder: parseInt(e.target.value) || 0 }))} />
                                </div>
                            </div>
                            <div>
                                <label className="vz-form-label" htmlFor="cg-content">Content <span style={{ color: '#e6533c' }}>*</span></label>
                                <textarea id="cg-content" className="vz-form-control" placeholder="Enter guideline content..." rows={7} value={form.content} onChange={e => setForm(f => ({ ...f, content: e.target.value }))} style={{ resize: 'vertical', fontFamily: 'inherit' }} />
                                {formErrors.content && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.content}</div>}
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                <input type="checkbox" id="cg-active" checked={form.isActive} onChange={e => setForm(f => ({ ...f, isActive: e.target.checked }))} style={{ width: 16, height: 16, cursor: 'pointer' }} />
                                <label htmlFor="cg-active" style={{ margin: 0, cursor: 'pointer', fontSize: '0.875rem', color: 'var(--vz-text-primary)', fontWeight: 500 }}>Active (visible to users)</label>
                            </div>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', padding: '1rem 1.5rem', borderTop: '1px solid var(--vz-border-color)' }}>
                            <button className="vz-btn vz-btn-outline" onClick={closeModal} disabled={saving}>Cancel</button>
                            <button id="cg-save-btn" className="vz-btn vz-btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving...' : editingId ? 'Update Guideline' : 'Create Guideline'}</button>
                        </div>
                    </div>
                </div>
            )}

            {/* Delete Confirm */}
            {deleteTarget && (
                <div style={{ position: 'fixed', inset: 0, zIndex: 1060, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }} onClick={e => { if (e.target === e.currentTarget && !deleting) setDeleteTarget(null); }}>
                    <div style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 12, width: '100%', maxWidth: 440, padding: '2rem', textAlign: 'center', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }}>
                        <div style={{ fontSize: '2.5rem', marginBottom: '1rem', color: '#e6533c' }}><BiTrash /></div>
                        <h6 style={{ fontWeight: 600, marginBottom: '0.5rem' }}>Delete Guideline?</h6>
                        <p style={{ color: 'var(--vz-text-muted)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>Are you sure you want to delete <strong>"{deleteTarget.title}"</strong>? This cannot be undone.</p>
                        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                            <button className="vz-btn vz-btn-outline" onClick={() => setDeleteTarget(null)} disabled={deleting}>Cancel</button>
                            <button id="cg-delete-confirm" className="vz-btn" style={{ background: '#e6533c', color: '#fff', border: 'none' }} onClick={handleDelete} disabled={deleting}>{deleting ? 'Deleting...' : 'Delete'}</button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default CommunityGuidelines;
