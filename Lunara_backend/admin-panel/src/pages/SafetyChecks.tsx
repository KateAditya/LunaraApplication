import React, { useState, useEffect } from 'react';
import { BiSearch, BiShieldQuarter, BiCheckCircle, BiError, BiMessageDetail } from 'react-icons/bi';
import toast from 'react-hot-toast';
import safetyCheckApi from '../api/safetyCheck';
import type { SafetyCheck } from '../api/safetyCheck';

export const SafetyChecks: React.FC = () => {
    const [checks, setChecks] = useState<SafetyCheck[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [filterSafe, setFilterSafe] = useState<string>('all');
    const [selectedCheck, setSelectedCheck] = useState<SafetyCheck | null>(null);
    const [feedbackText, setFeedbackText] = useState<string>('');
    const [submittingFeedback, setSubmittingFeedback] = useState(false);

    useEffect(() => {
        fetchSafetyChecks();
    }, []);

    const fetchSafetyChecks = async () => {
        try {
            setLoading(true);
            const res = await safetyCheckApi.getSafetyChecks();
            if (res.success) {
                setChecks(res.data);
            }
        } catch (error) {
            toast.error('Failed to load safety checks');
        } finally {
            setLoading(false);
        }
    };

    const handleFeedbackSubmit = async () => {
        if (!selectedCheck) return;
        if (!feedbackText.trim()) {
            toast.error('Please enter some feedback');
            return;
        }

        try {
            setSubmittingFeedback(true);
            const res = await safetyCheckApi.submitFeedback(selectedCheck.id, feedbackText.trim());
            if (res.success) {
                toast.success('Feedback sent and user notified!');
                setSelectedCheck(null);
                setFeedbackText('');
                fetchSafetyChecks();
            }
        } catch (error) {
            toast.error('Failed to send feedback');
        } finally {
            setSubmittingFeedback(false);
        }
    };

    // Calculate quick stats
    const totalChecks = checks.length;
    const feltSafeCount = checks.filter(c => c.feltSafe).length;
    const feltUnsafeCount = checks.filter(c => !c.feltSafe).length;
    const safetyRate = totalChecks > 0 ? ((feltSafeCount / totalChecks) * 100).toFixed(1) + '%' : '100%';

    const filtered = checks.filter((c) => {
        const matchesSearch = !search || 
            (c.user?.firstName + ' ' + c.user?.lastName).toLowerCase().includes(search.toLowerCase()) ||
            (c.partner?.firstName + ' ' + c.partner?.lastName).toLowerCase().includes(search.toLowerCase()) ||
            (c.opinion || '').toLowerCase().includes(search.toLowerCase());

        const matchesFilter = filterSafe === 'all' ||
            (filterSafe === 'safe' && c.feltSafe) ||
            (filterSafe === 'unsafe' && !c.feltSafe);

        return matchesSearch && matchesFilter;
    });

    return (
        <div>
            {/* Stats Cards */}
            <div className="row g-3 mb-4">
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-1">
                        <div className="d-flex justify-content-between align-items-start">
                            <div>
                                <div className="stat-card-label">Total Safety Checks</div>
                                <div className="stat-card-value">{totalChecks}</div>
                                <div className="text-muted" style={{ fontSize: '0.6875rem', marginTop: '0.25rem' }}>
                                    Total check submissions
                                </div>
                            </div>
                            <div className="stat-card-icon primary"><BiShieldQuarter /></div>
                        </div>
                    </div>
                </div>
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-2">
                        <div className="d-flex justify-content-between align-items-start">
                            <div>
                                <div className="stat-card-label">Felt Safe</div>
                                <div className="stat-card-value">{feltSafeCount}</div>
                                <div className="text-muted" style={{ fontSize: '0.6875rem', marginTop: '0.25rem' }}>
                                    Positive experiences reported
                                </div>
                            </div>
                            <div className="stat-card-icon success"><BiCheckCircle /></div>
                        </div>
                    </div>
                </div>
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-3">
                        <div className="d-flex justify-content-between align-items-start">
                            <div>
                                <div className="stat-card-label">Felt Unsafe</div>
                                <div className="stat-card-value text-danger">{feltUnsafeCount}</div>
                                <div className="text-muted" style={{ fontSize: '0.6875rem', marginTop: '0.25rem' }}>
                                    Requires review and feedback
                                </div>
                            </div>
                            <div className="stat-card-icon danger"><BiError /></div>
                        </div>
                    </div>
                </div>
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-4">
                        <div className="d-flex justify-content-between align-items-start">
                            <div>
                                <div className="stat-card-label">Overall Safety Score</div>
                                <div className="stat-card-value">{safetyRate}</div>
                                <div className="text-muted" style={{ fontSize: '0.6875rem', marginTop: '0.25rem' }}>
                                    Safe reports ratio
                                </div>
                            </div>
                            <div className="stat-card-icon info"><BiShieldQuarter /></div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Filter and Search controls */}
            <div className="vz-card mb-3">
                <div className="vz-card-body d-flex flex-wrap gap-3 align-items-center justify-content-between" style={{ padding: '0.75rem 1.25rem' }}>
                    <div className="d-flex gap-3 align-items-center">
                        <div style={{ position: 'relative', width: 220 }}>
                            <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                            <input
                                className="vz-form-control"
                                placeholder="Search by name or opinion..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                style={{ paddingLeft: '2.25rem' }}
                            />
                        </div>
                        <select 
                            className="vz-form-control" 
                            style={{ width: 160 }}
                            value={filterSafe}
                            onChange={(e) => setFilterSafe(e.target.value)}
                        >
                            <option value="all">All Submissions</option>
                            <option value="safe">Felt Safe</option>
                            <option value="unsafe">Felt Unsafe</option>
                        </select>
                    </div>
                    <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={fetchSafetyChecks}>
                        Refresh Data
                    </button>
                </div>
            </div>

            {/* Submissions List */}
            <div className="vz-card">
                <div className="table-responsive">
                    <table className="vz-table">
                        <thead>
                            <tr>
                                <th>Date</th>
                                <th>User (Reporter)</th>
                                <th>Partner (Subject)</th>
                                <th>Felt Safe</th>
                                <th>Prebuilt Answers</th>
                                <th>User Opinion</th>
                                <th>Admin Feedback</th>
                                <th>Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            {loading ? (
                                <tr><td colSpan={8} className="text-center py-4">Loading safety checks...</td></tr>
                            ) : filtered.length === 0 ? (
                                <tr><td colSpan={8} className="text-center py-4">No safety checks found</td></tr>
                            ) : (
                                filtered.map((check) => (
                                    <tr key={check.id}>
                                        <td style={{ fontSize: '12px' }}>
                                            {new Date(check.createdAt).toLocaleDateString()} <br />
                                            <span className="text-muted" style={{ fontSize: '10px' }}>
                                                {new Date(check.createdAt).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}
                                            </span>
                                        </td>
                                        <td>
                                            <div className="d-flex align-items-center gap-2">
                                                {check.user?.profileImageUrl ? (
                                                    <img 
                                                        src={check.user.profileImageUrl} 
                                                        alt="User" 
                                                        className="rounded-circle"
                                                        style={{ width: 32, height: 32, objectFit: 'cover' }}
                                                    />
                                                ) : (
                                                    <div 
                                                        className="rounded-circle d-flex align-items-center justify-content-center text-white fw-bold bg-primary"
                                                        style={{ width: 32, height: 32, fontSize: '12px' }}
                                                    >
                                                        {check.user?.firstName?.charAt(0) || 'U'}
                                                    </div>
                                                )}
                                                <div>
                                                    <div className="fw-bold">{check.user?.firstName} {check.user?.lastName}</div>
                                                    <span className="text-muted" style={{ fontSize: '10px' }}>ID: {check.userId.substring(0, 8)}...</span>
                                                </div>
                                            </div>
                                        </td>
                                        <td>
                                            <div className="d-flex align-items-center gap-2">
                                                {check.partner?.profileImageUrl ? (
                                                    <img 
                                                        src={check.partner.profileImageUrl} 
                                                        alt="Partner" 
                                                        className="rounded-circle"
                                                        style={{ width: 32, height: 32, objectFit: 'cover' }}
                                                    />
                                                ) : (
                                                    <div 
                                                        className="rounded-circle d-flex align-items-center justify-content-center text-white fw-bold bg-secondary"
                                                        style={{ width: 32, height: 32, fontSize: '12px' }}
                                                    >
                                                        {check.partner?.firstName?.charAt(0) || 'P'}
                                                    </div>
                                                )}
                                                <div>
                                                    <div className="fw-bold">{check.partner?.firstName} {check.partner?.lastName}</div>
                                                    <span className="text-muted" style={{ fontSize: '10px' }}>ID: {check.partnerId.substring(0, 8)}...</span>
                                                </div>
                                            </div>
                                        </td>
                                        <td>
                                            <span className={`vz-badge ${check.feltSafe ? 'success' : 'danger'}`}>
                                                {check.feltSafe ? 'YES' : 'NO'}
                                            </span>
                                        </td>
                                        <td>
                                            <div className="d-flex flex-wrap gap-1" style={{ maxWidth: 200 }}>
                                                {check.prebuiltAnswers && check.prebuiltAnswers.length > 0 ? (
                                                    check.prebuiltAnswers.map((answer, index) => (
                                                        <span key={index} className="vz-badge secondary" style={{ fontSize: '10px' }}>
                                                            {answer}
                                                        </span>
                                                    ))
                                                ) : (
                                                    <span className="text-muted" style={{ fontSize: '11px' }}>None</span>
                                                )}
                                            </div>
                                        </td>
                                        <td>
                                            <div 
                                                className="text-wrap" 
                                                style={{ maxWidth: 250, fontSize: '12px', wordBreak: 'break-word' }}
                                            >
                                                {check.opinion || <span className="text-muted italic">No custom opinion</span>}
                                            </div>
                                        </td>
                                        <td>
                                            <div 
                                                className="text-wrap text-success" 
                                                style={{ maxWidth: 250, fontSize: '12px', wordBreak: 'break-word', fontWeight: 500 }}
                                            >
                                                {check.adminFeedback || <span className="text-muted italic">No feedback sent</span>}
                                            </div>
                                        </td>
                                        <td>
                                            <button 
                                                className={`btn btn-sm ${check.adminFeedback ? 'btn-outline-primary' : 'btn-primary'} d-flex align-items-center gap-1`}
                                                onClick={() => {
                                                    setSelectedCheck(check);
                                                    setFeedbackText(check.adminFeedback || '');
                                                }}
                                            >
                                                <BiMessageDetail /> 
                                                {check.adminFeedback ? 'Edit Feedback' : 'Send Feedback'}
                                            </button>
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
            </div>

            {/* Send Feedback Modal */}
            {selectedCheck && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.5)' }}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content" style={{ borderRadius: '16px', overflow: 'hidden' }}>
                            <div className="modal-header bg-primary text-white">
                                <h5 className="modal-title">
                                    Send Feedback to {selectedCheck.user?.firstName}
                                </h5>
                                <button 
                                    type="button" 
                                    className="btn-close btn-close-white" 
                                    onClick={() => {
                                        setSelectedCheck(null);
                                        setFeedbackText('');
                                    }}
                                ></button>
                            </div>
                            <div className="modal-body" style={{ padding: '20px' }}>
                                <div className="mb-3">
                                    <label className="form-label fw-bold">Report Summary</label>
                                    <div className="p-3 bg-light rounded" style={{ fontSize: '13px' }}>
                                        <div>
                                            <strong>Partner:</strong> {selectedCheck.partner?.firstName} {selectedCheck.partner?.lastName}
                                        </div>
                                        <div className="mt-1">
                                            <strong>Felt Safe?</strong>{' '}
                                            <span className={`vz-badge ${selectedCheck.feltSafe ? 'success' : 'danger'}`}>
                                                {selectedCheck.feltSafe ? 'YES' : 'NO'}
                                            </span>
                                        </div>
                                        {selectedCheck.prebuiltAnswers && selectedCheck.prebuiltAnswers.length > 0 && (
                                            <div className="mt-2">
                                                <strong>Reasons:</strong> {selectedCheck.prebuiltAnswers.join(', ')}
                                            </div>
                                        )}
                                        {selectedCheck.opinion && (
                                            <div className="mt-2">
                                                <strong>User's Opinion:</strong> "{selectedCheck.opinion}"
                                            </div>
                                        )}
                                    </div>
                                </div>
                                <div className="mb-3">
                                    <label className="form-label fw-bold text-primary">Admin Feedback / Response</label>
                                    <textarea 
                                        className="form-control" 
                                        rows={4} 
                                        placeholder="Write an encouraging response, safety guidelines, or actions taken..."
                                        value={feedbackText} 
                                        onChange={(e) => setFeedbackText(e.target.value)}
                                        style={{ fontSize: '13px', borderRadius: '10px' }}
                                    />
                                    <div className="form-text text-muted" style={{ fontSize: '11px' }}>
                                        This feedback will appear as an in-app notification to the user.
                                    </div>
                                </div>
                            </div>
                            <div className="modal-footer">
                                <button 
                                    type="button" 
                                    className="btn btn-secondary" 
                                    onClick={() => {
                                        setSelectedCheck(null);
                                        setFeedbackText('');
                                    }}
                                    disabled={submittingFeedback}
                                >
                                    Cancel
                                </button>
                                <button 
                                    type="button" 
                                    className="btn btn-primary" 
                                    onClick={handleFeedbackSubmit}
                                    disabled={submittingFeedback}
                                >
                                    {submittingFeedback ? 'Sending...' : 'Send & Notify'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default SafetyChecks;
