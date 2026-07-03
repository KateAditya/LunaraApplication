import React, { useState, useEffect, useCallback } from 'react';
import { BiPlus, BiEdit, BiTrash, BiSearch, BiX, BiCheckCircle, BiFile } from 'react-icons/bi';
import toast from 'react-hot-toast';
import { legalApi } from '../api/supportLegal';
import type { LegalDocument, LegalDocumentType } from '../api/supportLegal';

const DOC_TYPES: { value: LegalDocumentType; label: string }[] = [
    { value: 'terms_of_service', label: 'Terms of Service' },
    { value: 'privacy_policy', label: 'Privacy Policy' },
    { value: 'refund_policy', label: 'Refund Policy' },
    { value: 'other', label: 'Other' },
];

const TYPE_LABELS: Record<LegalDocumentType, string> = {
    terms_of_service: 'Terms of Service',
    privacy_policy: 'Privacy Policy',
    refund_policy: 'Refund Policy',
    other: 'Other',
};

const today = new Date().toISOString().split('T')[0];
const emptyForm = { title: '', type: 'terms_of_service' as LegalDocumentType, content: '', version: '1.0', isActive: true, effectiveDate: today };

export const LegalTerms: React.FC = () => {
    const [documents, setDocuments] = useState<LegalDocument[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [filterType, setFilterType] = useState('');
    const [showModal, setShowModal] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState({ ...emptyForm });
    const [saving, setSaving] = useState(false);
    const [deleteTarget, setDeleteTarget] = useState<LegalDocument | null>(null);
    const [deleting, setDeleting] = useState(false);
    const [formErrors, setFormErrors] = useState<Record<string, string>>({});

    const fetchDocs = useCallback(async () => {
        setLoading(true);
        try {
            const res = await legalApi.getAll();
            setDocuments(res.documents || []);
        } catch { toast.error('Failed to load legal documents'); }
        finally { setLoading(false); }
    }, []);

    useEffect(() => { fetchDocs(); }, [fetchDocs]);

    const openAdd = () => { setForm({ ...emptyForm, effectiveDate: today }); setFormErrors({}); setEditingId(null); setShowModal(true); };
    const openEdit = (d: LegalDocument) => {
        setForm({ title: d.title, type: d.type, content: d.content, version: d.version, isActive: d.isActive, effectiveDate: d.effectiveDate?.split('T')[0] || today });
        setFormErrors({}); setEditingId(d.id); setShowModal(true);
    };
    const closeModal = () => { setShowModal(false); setEditingId(null); };

    const validate = () => {
        const e: Record<string, string> = {};
        if (!form.title.trim()) e.title = 'Title is required';
        if (!form.type) e.type = 'Type is required';
        if (!form.content.trim()) e.content = 'Content is required';
        if (!form.version.trim()) e.version = 'Version is required';
        if (!form.effectiveDate) e.effectiveDate = 'Effective date is required';
        setFormErrors(e);
        return Object.keys(e).length === 0;
    };

    const handleSave = async () => {
        if (!validate()) return;
        setSaving(true);
        try {
            if (editingId) { await legalApi.update(editingId, form); toast.success('Document updated'); }
            else { await legalApi.create(form); toast.success('Document created'); }
            closeModal(); fetchDocs();
        } catch (err: any) {
            toast.error(err?.response?.data?.message || 'Failed to save document');
        } finally { setSaving(false); }
    };

    const handleDelete = async () => {
        if (!deleteTarget) return;
        setDeleting(true);
        try {
            await legalApi.delete(deleteTarget.id);
            toast.success('Document deleted'); setDeleteTarget(null); fetchDocs();
        } catch { toast.error('Failed to delete document'); }
        finally { setDeleting(false); }
    };

    const filtered = documents.filter(d =>
        (!search || d.title.toLowerCase().includes(search.toLowerCase()) || TYPE_LABELS[d.type].toLowerCase().includes(search.toLowerCase())) &&
        (!filterType || d.type === filterType)
    );

    const stats = [
        { label: 'Total Documents', value: documents.length, icon: <BiFile />, cls: 'primary' },
        { label: 'Active', value: documents.filter(d => d.isActive).length, icon: <BiCheckCircle />, cls: 'success' },
        { label: 'Inactive', value: documents.filter(d => !d.isActive).length, icon: <BiFile />, cls: 'warning' },
        { label: 'Document Types', value: [...new Set(documents.map(d => d.type))].length, icon: <BiFile />, cls: 'info' },
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
                    <h6 className="vz-card-title">Legal & Terms Documents</h6>
                    <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
                        <div style={{ position: 'relative' }}>
                            <BiSearch style={{ position: 'absolute', left: 8, top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)', fontSize: '0.875rem' }} />
                            <input id="lt-search" className="vz-form-control" style={{ paddingLeft: '1.75rem', width: 200 }} placeholder="Search documents..." value={search} onChange={e => setSearch(e.target.value)} />
                        </div>
                        <select id="lt-filter-type" className="vz-form-select" style={{ width: 'auto' }} value={filterType} onChange={e => setFilterType(e.target.value)}>
                            <option value="">All Types</option>
                            {DOC_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                        </select>
                        <button id="lt-add-btn" className="vz-btn vz-btn-primary vz-btn-sm" onClick={openAdd}><BiPlus /> Add Document</button>
                    </div>
                </div>
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {loading ? (
                        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>Loading...</div>
                    ) : filtered.length === 0 ? (
                        <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <BiFile style={{ fontSize: '2.5rem', display: 'block', margin: '0 auto 0.5rem' }} />
                            No documents found.{!search && !filterType && <> <span style={{ cursor: 'pointer', color: 'var(--vz-primary)' }} onClick={openAdd}>Add the first one.</span></>}
                        </div>
                    ) : (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr><th>Title</th><th>Type</th><th>Version</th><th>Effective Date</th><th>Status</th><th style={{ textAlign: 'right' }}>Actions</th></tr>
                                </thead>
                                <tbody>
                                    {filtered.map(d => (
                                        <tr key={d.id}>
                                            <td style={{ fontWeight: 500, maxWidth: 220 }}><div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{d.title}</div></td>
                                            <td><span className="vz-badge primary">{TYPE_LABELS[d.type]}</span></td>
                                            <td style={{ color: 'var(--vz-text-muted)', fontWeight: 500 }}>v{d.version}</td>
                                            <td style={{ color: 'var(--vz-text-muted)', fontSize: '0.75rem' }}>{d.effectiveDate ? new Date(d.effectiveDate).toLocaleDateString() : '-'}</td>
                                            <td><span className={`vz-badge ${d.isActive ? 'success' : 'secondary'}`}>{d.isActive ? 'Active' : 'Inactive'}</span></td>
                                            <td style={{ textAlign: 'right' }}>
                                                <div style={{ display: 'flex', gap: '0.25rem', justifyContent: 'flex-end' }}>
                                                    <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={() => openEdit(d)} title="Edit"><BiEdit /></button>
                                                    <button className="vz-btn vz-btn-sm" style={{ background: 'rgba(230,83,60,0.1)', color: '#e6533c', border: '1px solid rgba(230,83,60,0.2)' }} onClick={() => setDeleteTarget(d)} title="Delete"><BiTrash /></button>
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
                    <div style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 12, width: '100%', maxWidth: 660, maxHeight: '90vh', overflow: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '1.25rem 1.5rem', borderBottom: '1px solid var(--vz-border-color)' }}>
                            <h6 style={{ margin: 0, fontWeight: 600, color: 'var(--vz-text-primary)' }}>{editingId ? 'Edit Legal Document' : 'Add Legal Document'}</h6>
                            <button onClick={closeModal} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--vz-text-muted)', fontSize: '1.25rem' }}><BiX /></button>
                        </div>
                        <div style={{ padding: '1.5rem', display: 'grid', gap: '1rem' }}>
                            <div>
                                <label className="vz-form-label" htmlFor="lt-title">Title <span style={{ color: '#e6533c' }}>*</span></label>
                                <input id="lt-title" className="vz-form-control" placeholder="Enter document title" value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))} />
                                {formErrors.title && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.title}</div>}
                            </div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '1rem' }}>
                                <div>
                                    <label className="vz-form-label" htmlFor="lt-type">Type <span style={{ color: '#e6533c' }}>*</span></label>
                                    <select id="lt-type" className="vz-form-select" value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value as LegalDocumentType }))}>
                                        {DOC_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                                    </select>
                                    {formErrors.type && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.type}</div>}
                                </div>
                                <div>
                                    <label className="vz-form-label" htmlFor="lt-version">Version <span style={{ color: '#e6533c' }}>*</span></label>
                                    <input id="lt-version" className="vz-form-control" placeholder="e.g. 1.0" value={form.version} onChange={e => setForm(f => ({ ...f, version: e.target.value }))} />
                                    {formErrors.version && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.version}</div>}
                                </div>
                                <div>
                                    <label className="vz-form-label" htmlFor="lt-effective-date">Effective Date <span style={{ color: '#e6533c' }}>*</span></label>
                                    <input id="lt-effective-date" type="date" className="vz-form-control" value={form.effectiveDate} onChange={e => setForm(f => ({ ...f, effectiveDate: e.target.value }))} />
                                    {formErrors.effectiveDate && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.effectiveDate}</div>}
                                </div>
                            </div>
                            <div>
                                <label className="vz-form-label" htmlFor="lt-content">Content <span style={{ color: '#e6533c' }}>*</span></label>
                                <textarea id="lt-content" className="vz-form-control" placeholder="Enter full legal document content..." rows={8} value={form.content} onChange={e => setForm(f => ({ ...f, content: e.target.value }))} style={{ resize: 'vertical', fontFamily: 'inherit' }} />
                                {formErrors.content && <div style={{ fontSize: '0.75rem', color: '#e6533c', marginTop: 4 }}>{formErrors.content}</div>}
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                <input type="checkbox" id="lt-active" checked={form.isActive} onChange={e => setForm(f => ({ ...f, isActive: e.target.checked }))} style={{ width: 16, height: 16, cursor: 'pointer' }} />
                                <label htmlFor="lt-active" style={{ margin: 0, cursor: 'pointer', fontSize: '0.875rem', color: 'var(--vz-text-primary)', fontWeight: 500 }}>Active (visible to users)</label>
                            </div>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', padding: '1rem 1.5rem', borderTop: '1px solid var(--vz-border-color)' }}>
                            <button className="vz-btn vz-btn-outline" onClick={closeModal} disabled={saving}>Cancel</button>
                            <button id="lt-save-btn" className="vz-btn vz-btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving...' : editingId ? 'Update Document' : 'Create Document'}</button>
                        </div>
                    </div>
                </div>
            )}

            {/* Delete Confirm */}
            {deleteTarget && (
                <div style={{ position: 'fixed', inset: 0, zIndex: 1060, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }} onClick={e => { if (e.target === e.currentTarget && !deleting) setDeleteTarget(null); }}>
                    <div style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 12, width: '100%', maxWidth: 440, padding: '2rem', textAlign: 'center', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }}>
                        <div style={{ fontSize: '2.5rem', marginBottom: '1rem', color: '#e6533c' }}><BiTrash /></div>
                        <h6 style={{ fontWeight: 600, marginBottom: '0.5rem' }}>Delete Document?</h6>
                        <p style={{ color: 'var(--vz-text-muted)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>Are you sure you want to delete <strong>"{deleteTarget.title}"</strong>? This cannot be undone.</p>
                        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                            <button className="vz-btn vz-btn-outline" onClick={() => setDeleteTarget(null)} disabled={deleting}>Cancel</button>
                            <button id="lt-delete-confirm" className="vz-btn" style={{ background: '#e6533c', color: '#fff', border: 'none' }} onClick={handleDelete} disabled={deleting}>{deleting ? 'Deleting...' : 'Delete'}</button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default LegalTerms;
