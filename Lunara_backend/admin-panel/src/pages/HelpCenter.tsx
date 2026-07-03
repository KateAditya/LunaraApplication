import React, { useState, useEffect, useCallback } from 'react';
import { BiPlus, BiEdit, BiTrash, BiSearch, BiX, BiCheckCircle, BiError, BiHelpCircle } from 'react-icons/bi';
import toast from 'react-hot-toast';
import { helpCenterApi } from '../api/supportLegal';
import type { HelpArticle } from '../api/supportLegal';

const CATEGORIES = ['General', 'Account', 'Booking', 'Payment', 'Venue', 'Safety', 'Technical', 'Other'];

const emptyForm = { title: '', content: '', category: 'General', isPublished: false, displayOrder: 0 };

export const HelpCenter: React.FC = () => {
    const [articles, setArticles] = useState<HelpArticle[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [filterCat, setFilterCat] = useState('');
    const [showModal, setShowModal] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState({ ...emptyForm });
    const [saving, setSaving] = useState(false);
    const [deleteTarget, setDeleteTarget] = useState<HelpArticle | null>(null);
    const [deleting, setDeleting] = useState(false);
    const [formErrors, setFormErrors] = useState<Record<string, string>>({});

    const fetchArticles = useCallback(async () => {
        setLoading(true);
        try {
            const res = await helpCenterApi.getAll();
            setArticles(res.articles || []);
        } catch { toast.error('Failed to load help articles'); }
        finally { setLoading(false); }
    }, []);

    useEffect(() => { fetchArticles(); }, [fetchArticles]);

    const openAdd = () => { setForm({ ...emptyForm }); setFormErrors({}); setEditingId(null); setShowModal(true); };
    const openEdit = (a: HelpArticle) => {
        setForm({ title: a.title, content: a.content, category: a.category, isPublished: a.isPublished, displayOrder: a.displayOrder });
        setFormErrors({}); setEditingId(a.id); setShowModal(true);
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
            if (editingId) { await helpCenterApi.update(editingId, form); toast.success('Article updated'); }
            else { await helpCenterApi.create(form); toast.success('Article created'); }
            closeModal(); fetchArticles();
        } catch (err: any) {
            toast.error(err?.response?.data?.message || 'Failed to save article');
        } finally { setSaving(false); }
    };

    const handleDelete = async () => {
        if (!deleteTarget) return;
        setDeleting(true);
        try {
            await helpCenterApi.delete(deleteTarget.id);
            toast.success('Article deleted'); setDeleteTarget(null); fetchArticles();
        } catch { toast.error('Failed to delete article'); }
        finally { setDeleting(false); }
    };

    const filtered = articles.filter(a =>
        (!search || a.title.toLowerCase().includes(search.toLowerCase()) || a.category.toLowerCase().includes(search.toLowerCase())) &&
        (!filterCat || a.category === filterCat)
    );

    const stats = [
        { label: 'Total Articles', value: articles.length, icon: <BiHelpCircle />, cls: 'primary' },
        { label: 'Published', value: articles.filter(a => a.isPublished).length, icon: <BiCheckCircle />, cls: 'success' },
        { label: 'Drafts', value: articles.filter(a => !a.isPublished).length, icon: <BiError />, cls: 'warning' },
        { label: 'Categories', value: [...new Set(articles.map(a => a.category))].length, icon: <BiHelpCircle />, cls: 'info' },
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
                    <h6 className="vz-card-title">Help Articles</h6>
                    <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
                        <div style={{ position: 'relative' }}>
                            <BiSearch style={{ position: 'absolute', left: 8, top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)', fontSize: '0.875rem' }} />
                            <input id="help-search" className="vz-form-control" style={{ paddingLeft: '1.75rem', width: 200 }} placeholder="Search articles..." value={search} onChange={e => setSearch(e.target.value)} />
                        </div>
                        <select id="help-filter-cat" className="vz-form-select" style={{ width: 'auto' }} value={filterCat} onChange={e => setFilterCat(e.target.value)}>
                            <option value="">All Categories</option>
                            {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
                        </select>
                        <button id="help-add-btn" className="vz-btn vz-btn-primary vz-btn-sm" onClick={openAdd}><BiPlus /> Add Article</button>
                    </div>
                </div>
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {loading ? (
                        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>Loading...</div>
                    ) : filtered.length === 0 ? (
                        <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <BiHelpCircle style={{ fontSize: '2.5rem', display: 'block', margin: '0 auto 0.5rem' }} />
                            No articles found.{!search && !filterCat && <> <span style={{ cursor: 'pointer', color: 'var(--vz-primary)' }} onClick={openAdd}>Add the first one.</span></>}
                        </div>
                    ) : (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr><th>Title</th><th>Category</th><th>Status</th><th>Order</th><th>Created</th><th style={{ textAlign: 'right' }}>Actions</th></tr>
                                </thead>
                                <tbody>
                                    {filtered.map(a => (
                                        <tr key={a.id}>
                                            <td style={{ fontWeight: 500, maxWidth: 260 }}><div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.title}</div></td>
                                            <td><span className="vz-badge info">{a.category}</span></td>
                                            <td><span className={`vz-badge ${a.isPublished ? 'success' : 'warning'}`}>{a.isPublished ? 'Published' : 'Draft'}</span></td>
                                            <td style={{ color: 'var(--vz-text-muted)' }}>{a.displayOrder}</td>
                                            <td style={{ color: 'var(--vz-text-muted)', fontSize: '0.75rem' }}>{new Date(a.createdAt).toLocaleDateString()}</td>
                                            <td style={{ textAlign: 'right' }}>
                                                <div style={{ display: 'flex', gap: '0.25rem', justifyContent: 'flex-end' }}>
                                                    <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={() => openEdit(a)} title="Edit"><BiEdit /></button>
                                                    <button className="vz-btn vz-btn-sm" style={{ background: 'rgba(230,83,60,0.1)', color: '#e6533c', border: '1px solid rgba(230,83,60,0.2)' }} onClick={() => setDeleteTarget(a)} title="Delete"><BiTrash /></button>
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
                            <h6 style={{ margin: 0, fontWeight: 600, color: 'var(--vz-text-primary)' }}>{editingId ? 'Edit Help Article' : 'Add Help Article'}</h6>
                            <button onClick={closeModal} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--vz-text-muted)', fontSize: '1.25rem' }}><BiX /></button>
                        </div>
                        <div style={{ padding: '1.5rem', display: 'grid', gap: '1rem' }}>
                            <div>
                                <label className="vz-form-label" htmlFor="ha-title">Title <span style={{ color: '#e6533c' }}>*</span></label>
                                <input id="ha-title" className="vz-form-control" placeholder="Enter article title" value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))} />
                                {formErrors.title && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.title}</div>}
                            </div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>
                                <div>
                                    <label className="vz-form-label" htmlFor="ha-category">Category <span style={{ color: '#e6533c' }}>*</span></label>
                                    <select id="ha-category" className="vz-form-select" value={form.category} onChange={e => setForm(f => ({ ...f, category: e.target.value }))}>
                                        {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
                                    </select>
                                    {formErrors.category && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.category}</div>}
                                </div>
                                <div>
                                    <label className="vz-form-label" htmlFor="ha-order">Display Order</label>
                                    <input id="ha-order" type="number" className="vz-form-control" placeholder="0" min={0} value={form.displayOrder} onChange={e => setForm(f => ({ ...f, displayOrder: parseInt(e.target.value) || 0 }))} />
                                </div>
                            </div>
                            <div>
                                <label className="vz-form-label" htmlFor="ha-content">Content <span style={{ color: '#e6533c' }}>*</span></label>
                                <textarea id="ha-content" className="vz-form-control" placeholder="Enter article content..." rows={7} value={form.content} onChange={e => setForm(f => ({ ...f, content: e.target.value }))} style={{ resize: 'vertical', fontFamily: 'inherit' }} />
                                {formErrors.content && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.content}</div>}
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                <input type="checkbox" id="ha-published" checked={form.isPublished} onChange={e => setForm(f => ({ ...f, isPublished: e.target.checked }))} style={{ width: 16, height: 16, cursor: 'pointer' }} />
                                <label htmlFor="ha-published" style={{ margin: 0, cursor: 'pointer', fontSize: '0.875rem', color: 'var(--vz-text-primary)', fontWeight: 500 }}>Publish this article</label>
                            </div>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', padding: '1rem 1.5rem', borderTop: '1px solid var(--vz-border-color)' }}>
                            <button className="vz-btn vz-btn-outline" onClick={closeModal} disabled={saving}>Cancel</button>
                            <button id="ha-save-btn" className="vz-btn vz-btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving...' : editingId ? 'Update Article' : 'Create Article'}</button>
                        </div>
                    </div>
                </div>
            )}

            {/* Delete Confirm Modal */}
            {deleteTarget && (
                <div style={{ position: 'fixed', inset: 0, zIndex: 1060, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }} onClick={e => { if (e.target === e.currentTarget && !deleting) setDeleteTarget(null); }}>
                    <div style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 12, width: '100%', maxWidth: 440, padding: '2rem', textAlign: 'center', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }}>
                        <div style={{ fontSize: '2.5rem', marginBottom: '1rem', color: '#e6533c' }}><BiTrash /></div>
                        <h6 style={{ fontWeight: 600, marginBottom: '0.5rem' }}>Delete Article?</h6>
                        <p style={{ color: 'var(--vz-text-muted)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>Are you sure you want to delete <strong>"{deleteTarget.title}"</strong>? This cannot be undone.</p>
                        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                            <button className="vz-btn vz-btn-outline" onClick={() => setDeleteTarget(null)} disabled={deleting}>Cancel</button>
                            <button id="ha-delete-confirm" className="vz-btn" style={{ background: '#e6533c', color: '#fff', border: 'none' }} onClick={handleDelete} disabled={deleting}>{deleting ? 'Deleting...' : 'Delete'}</button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default HelpCenter;
