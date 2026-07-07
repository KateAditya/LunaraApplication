import React, { useState, useEffect } from 'react';
import { BiSearch } from 'react-icons/bi';
import toast from 'react-hot-toast';
import bookingsApi from '../api/bookings';

export const LargePartyRequests: React.FC = () => {
    const [requests, setRequests] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [selectedRequest, setSelectedRequest] = useState<any | null>(null);
    const [amount, setAmount] = useState<string>('');

    // Payment sending state
    const [selectedPaymentRequest, setSelectedPaymentRequest] = useState<any | null>(null);
    const [paymentLink, setPaymentLink] = useState<string>('');
    const [paymentAmount, setPaymentAmount] = useState<string>('');

    useEffect(() => {
        fetchRequests();
    }, []);

    const fetchRequests = async () => {
        try {
            setLoading(true);
            const res = await bookingsApi.getLargePartyRequests();
            if (res.success) {
                setRequests(res.data);
            }
        } catch (error) {
            toast.error('Failed to load party requests');
        } finally {
            setLoading(false);
        }
    };

    const handleApprove = async () => {
        if (!selectedRequest || !amount || isNaN(Number(amount))) {
            toast.error('Please enter a valid amount');
            return;
        }

        try {
            const res = await bookingsApi.approveLargePartyRequest(selectedRequest.id, 'approved', Number(amount));
            if (res.success) {
                toast.success('Request approved successfully');
                setSelectedRequest(null);
                setAmount('');
                fetchRequests();
            }
        } catch (error) {
            toast.error('Failed to approve request');
        }
    };

    const handleReject = async (id: string) => {
        try {
            const res = await bookingsApi.approveLargePartyRequest(id, 'rejected');
            if (res.success) {
                toast.success('Request rejected');
                fetchRequests();
            }
        } catch (error) {
            toast.error('Failed to reject request');
        }
    };

    const handleSendPaymentLink = async () => {
        if (!selectedPaymentRequest || !paymentLink || !paymentLink.startsWith('http')) {
            toast.error('Please enter a valid payment link (starting with http/https)');
            return;
        }
        if (!paymentAmount || isNaN(Number(paymentAmount)) || Number(paymentAmount) <= 0) {
            toast.error('Please enter a valid amount');
            return;
        }

        try {
            const res = await bookingsApi.sendPaymentLink(selectedPaymentRequest.id, paymentLink, Number(paymentAmount));
            if (res.success) {
                toast.success('Payment link sent successfully');
                setSelectedPaymentRequest(null);
                setPaymentLink('');
                setPaymentAmount('');
                fetchRequests();
            }
        } catch (error) {
            toast.error('Failed to send payment link');
        }
    };

    const handleMarkPaymentDone = async (id: string) => {
        try {
            const res = await bookingsApi.markPaymentDone(id);
            if (res.success) {
                toast.success('Payment marked as completed');
                fetchRequests();
            }
        } catch (error) {
            toast.error('Failed to mark payment as done');
        }
    };

    const filtered = requests.filter((r) => {
        return !search || r.partySubject?.toLowerCase().includes(search.toLowerCase()) || 
               r.customer?.firstName?.toLowerCase().includes(search.toLowerCase()) ||
               r.venue?.name?.toLowerCase().includes(search.toLowerCase());
    });

    return (
        <div>
            <h4 className="mb-4">Large Party Requests</h4>

            <div className="vz-card mb-3">
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ position: 'relative', width: 220 }}>
                        <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                        <input
                            className="vz-form-control"
                            placeholder="Search requests..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            style={{ paddingLeft: '2.25rem' }}
                        />
                    </div>
                </div>
            </div>

            <div className="vz-card">
                <div className="table-responsive">
                    <table className="vz-table">
                        <thead>
                            <tr>
                                <th>Booking ID</th>
                                <th>User</th>
                                <th>Contact Info</th>
                                <th>Venue</th>
                                <th>Date & Time</th>
                                <th>Guests</th>
                                <th>Subject</th>
                                <th>Status</th>
                                <th>Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            {loading ? (
                                <tr><td colSpan={9} className="text-center py-4">Loading...</td></tr>
                            ) : filtered.length === 0 ? (
                                <tr><td colSpan={9} className="text-center py-4">No requests found</td></tr>
                            ) : (
                                filtered.map((req) => (
                                    <tr key={req.id}>
                                        <td>{req.bookingNumber}</td>
                                        <td>{req.customer?.firstName} {req.customer?.lastName}</td>
                                        <td>
                                            <div className="fw-bold">{req.mobileNumber || 'N/A'}</div>
                                            {req.optionalMobileNumber && <div className="text-muted" style={{ fontSize: '11px' }}>Alt: {req.optionalMobileNumber}</div>}
                                        </td>
                                        <td>{req.venue?.name}</td>
                                        <td>{new Date(req.bookingDate).toLocaleDateString()} {req.startTime}</td>
                                        <td>{req.numberOfGuests}</td>
                                        <td>{req.partySubject}</td>
                                        <td>
                                            <span className={`badge bg-${
                                                req.adminApprovalStatus === 'payment_done' ? 'success' :
                                                req.adminApprovalStatus === 'payment_sent' ? 'info' :
                                                req.adminApprovalStatus === 'approved' ? 'primary' :
                                                req.adminApprovalStatus === 'rejected' ? 'danger' : 'warning'
                                            }`}>
                                                {(req.adminApprovalStatus || 'PENDING').toUpperCase().replace('_', ' ')}
                                            </span>
                                        </td>
                                        <td>
                                            {(!req.adminApprovalStatus || req.adminApprovalStatus === 'pending') && (
                                                <div className="d-flex gap-2">
                                                    <button className="btn btn-sm btn-success" onClick={() => setSelectedRequest(req)}>Approve</button>
                                                    <button className="btn btn-sm btn-danger" onClick={() => handleReject(req.id)}>Reject</button>
                                                </div>
                                            )}
                                            {req.adminApprovalStatus === 'approved' && (
                                                <div className="d-flex flex-column gap-1">
                                                    <span className="fw-bold text-success">Approved: ₹{req.totalAmount}</span>
                                                    <button className="btn btn-sm btn-primary" onClick={() => {
                                                        setSelectedPaymentRequest(req);
                                                        setPaymentAmount(String(req.totalAmount || ''));
                                                        setPaymentLink('');
                                                    }}>Send Payment Link</button>
                                                </div>
                                            )}
                                            {req.adminApprovalStatus === 'payment_sent' && (
                                                <div className="d-flex flex-column gap-1">
                                                    <span className="fw-bold text-info">Amt: ₹{req.adminPaymentAmount || req.totalAmount}</span>
                                                    <a href={req.adminPaymentLink} target="_blank" rel="noopener noreferrer" className="text-truncate d-inline-block text-primary" style={{ maxWidth: '120px', fontSize: '11px' }}>Link</a>
                                                    <button className="btn btn-sm btn-warning" onClick={() => handleMarkPaymentDone(req.id)}>Mark Paid</button>
                                                </div>
                                            )}
                                            {req.adminApprovalStatus === 'payment_done' && (
                                                <div className="text-success fw-bold d-flex flex-column">
                                                    <span>Paid: ₹{req.adminPaymentAmount || req.totalAmount}</span>
                                                    <span style={{ fontSize: '10px' }} className="text-muted">Payment Done</span>
                                                </div>
                                            )}
                                            {req.adminApprovalStatus === 'rejected' && (
                                                <span className="text-danger fw-bold">Rejected</span>
                                            )}
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
            </div>

            {selectedRequest && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.5)' }}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content">
                            <div className="modal-header">
                                <h5 className="modal-title">Approve Party Request</h5>
                                <button type="button" className="btn-close" onClick={() => setSelectedRequest(null)}></button>
                            </div>
                            <div className="modal-body">
                                <div className="mb-3">
                                    <label className="form-label">User</label>
                                    <input type="text" className="form-control" value={`${selectedRequest.customer?.firstName} ${selectedRequest.customer?.lastName}`} disabled />
                                </div>
                                <div className="row mb-3">
                                    <div className="col-md-6">
                                        <label className="form-label">Mobile Number</label>
                                        <input type="text" className="form-control" value={selectedRequest.mobileNumber || 'N/A'} disabled />
                                    </div>
                                    <div className="col-md-6">
                                        <label className="form-label">Additional Mobile</label>
                                        <input type="text" className="form-control" value={selectedRequest.optionalMobileNumber || 'N/A'} disabled />
                                    </div>
                                </div>
                                <div className="mb-3">
                                    <label className="form-label">Subject</label>
                                    <input type="text" className="form-control" value={selectedRequest.partySubject || ''} disabled />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label">Requirement</label>
                                    <input type="text" className="form-control" value={selectedRequest.partyRequirement || ''} disabled />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label">Description</label>
                                    <textarea className="form-control" value={selectedRequest.partyDescription || ''} disabled rows={3} />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label text-primary fw-bold">Set Total Payment Amount (₹)</label>
                                    <input type="number" className="form-control" placeholder="Enter amount" value={amount} onChange={(e) => setAmount(e.target.value)} />
                                </div>
                            </div>
                            <div className="modal-footer">
                                <button type="button" className="btn btn-secondary" onClick={() => setSelectedRequest(null)}>Cancel</button>
                                <button type="button" className="btn btn-primary" onClick={handleApprove}>Confirm & Approve</button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {selectedPaymentRequest && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.5)' }}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content">
                            <div className="modal-header">
                                <h5 className="modal-title">Send Payment Link</h5>
                                <button type="button" className="btn-close" onClick={() => setSelectedPaymentRequest(null)}></button>
                            </div>
                            <div className="modal-body">
                                <div className="mb-3">
                                    <label className="form-label">Customer</label>
                                    <input type="text" className="form-control" value={`${selectedPaymentRequest.customer?.firstName} ${selectedPaymentRequest.customer?.lastName}`} disabled />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label">Approved Amount (₹)</label>
                                    <input type="number" className="form-control" value={paymentAmount} onChange={(e) => setPaymentAmount(e.target.value)} />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label fw-bold text-primary">Payment Link URL</label>
                                    <input type="text" className="form-control" placeholder="https://rzp.io/i/..." value={paymentLink} onChange={(e) => setPaymentLink(e.target.value)} />
                                    <div className="form-text">Must be a valid URL starting with http/https</div>
                                </div>
                            </div>
                            <div className="modal-footer">
                                <button type="button" className="btn btn-secondary" onClick={() => setSelectedPaymentRequest(null)}>Cancel</button>
                                <button type="button" className="btn btn-primary" onClick={handleSendPaymentLink}>Send Link</button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};
export default LargePartyRequests;
