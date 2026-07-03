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
                                <tr><td colSpan={8} className="text-center py-4">Loading...</td></tr>
                            ) : filtered.length === 0 ? (
                                <tr><td colSpan={8} className="text-center py-4">No requests found</td></tr>
                            ) : (
                                filtered.map((req) => (
                                    <tr key={req.id}>
                                        <td>{req.bookingNumber}</td>
                                        <td>{req.customer?.firstName} {req.customer?.lastName}</td>
                                        <td>{req.venue?.name}</td>
                                        <td>{new Date(req.bookingDate).toLocaleDateString()} {req.startTime}</td>
                                        <td>{req.numberOfGuests}</td>
                                        <td>{req.partySubject}</td>
                                        <td>
                                            <span className={`badge bg-${req.adminApprovalStatus === 'approved' ? 'success' : req.adminApprovalStatus === 'rejected' ? 'danger' : 'warning'}`}>
                                                {req.adminApprovalStatus?.toUpperCase() || 'PENDING'}
                                            </span>
                                        </td>
                                        <td>
                                            {req.adminApprovalStatus === 'pending' && (
                                                <div className="d-flex gap-2">
                                                    <button className="btn btn-sm btn-primary" onClick={() => setSelectedRequest(req)}>Approve</button>
                                                    <button className="btn btn-sm btn-danger" onClick={() => handleReject(req.id)}>Reject</button>
                                                </div>
                                            )}
                                            {req.adminApprovalStatus === 'approved' && <span>₹{req.totalAmount}</span>}
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
        </div>
    );
};
export default LargePartyRequests;
