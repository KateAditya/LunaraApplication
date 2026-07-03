import React, { useState } from 'react';
import { BiSearch, BiCalendar, BiGroup, BiCheckCircle, BiXCircle, BiTimeFive } from 'react-icons/bi';

const mockBookings = [
    { id: 'BK-2547', user: 'Rahul Sharma', venue: 'Club Infinity', date: '2026-02-21', time: '9:00 PM', guests: 4, amount: 8500, status: 'Confirmed' },
    { id: 'BK-2546', user: 'Priya Kapoor', venue: 'Skybar Lounge', date: '2026-02-21', time: '10:00 PM', guests: 2, amount: 4200, status: 'Pending' },
    { id: 'BK-2545', user: 'Arjun Mehta', venue: 'The Velvet Room', date: '2026-02-22', time: '8:00 PM', guests: 6, amount: 12000, status: 'Confirmed' },
    { id: 'BK-2544', user: 'Neha Reddy', venue: 'Grand Terrace', date: '2026-02-22', time: '9:00 PM', guests: 3, amount: 6800, status: 'Cancelled' },
    { id: 'BK-2543', user: 'Vikram Patel', venue: 'Neon District', date: '2026-02-20', time: '11:00 PM', guests: 8, amount: 18000, status: 'Confirmed' },
    { id: 'BK-2542', user: 'Ananya Singh', venue: 'Beach Cafe', date: '2026-02-20', time: '7:00 PM', guests: 2, amount: 3500, status: 'Confirmed' },
    { id: 'BK-2541', user: 'Rohan Gupta', venue: 'Club Infinity', date: '2026-02-19', time: '10:00 PM', guests: 5, amount: 9500, status: 'Pending' },
    { id: 'BK-2540', user: 'Meera Joshi', venue: 'Skybar Lounge', date: '2026-02-19', time: '8:30 PM', guests: 4, amount: 7200, status: 'Cancelled' },
    { id: 'BK-2539', user: 'Karthik Menon', venue: 'The Velvet Room', date: '2026-02-18', time: '9:30 PM', guests: 3, amount: 5800, status: 'Confirmed' },
    { id: 'BK-2538', user: 'Divya Nair', venue: 'Grand Terrace', date: '2026-02-18', time: '10:00 PM', guests: 6, amount: 14000, status: 'Confirmed' },
];

const getStatusBadge = (status: string) => {
    const map: Record<string, string> = { Confirmed: 'success', Pending: 'warning', Cancelled: 'danger' };
    return map[status] || 'secondary';
};

export const Bookings: React.FC = () => {
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState('all');
    const [currentPage, setCurrentPage] = useState(1);
    const perPage = 10;

    const filtered = mockBookings.filter((b) => {
        const matchSearch = !search || b.user.toLowerCase().includes(search.toLowerCase()) ||
            b.venue.toLowerCase().includes(search.toLowerCase()) || b.id.toLowerCase().includes(search.toLowerCase());
        const matchStatus = statusFilter === 'all' || b.status === statusFilter;
        return matchSearch && matchStatus;
    });
    const paged = filtered.slice((currentPage - 1) * perPage, currentPage * perPage);

    const totalRevenue = mockBookings.reduce((s, b) => s + b.amount, 0);
    const confirmed = mockBookings.filter(b => b.status === 'Confirmed').length;
    const pending = mockBookings.filter(b => b.status === 'Pending').length;
    const cancelled = mockBookings.filter(b => b.status === 'Cancelled').length;

    return (
        <div>
            {/* Stat Cards */}
            <div className="row g-3 mb-4">
                {[
                    { label: 'Total Bookings', value: mockBookings.length, icon: <BiCalendar />, cls: 'primary' },
                    { label: 'Confirmed', value: confirmed, icon: <BiCheckCircle />, cls: 'success' },
                    { label: 'Pending', value: pending, icon: <BiTimeFive />, cls: 'warning' },
                    { label: 'Cancelled', value: cancelled, icon: <BiXCircle />, cls: 'danger' },
                ].map((s, i) => (
                    <div className="col-sm-6 col-xl-3" key={s.label}>
                        <div className={`stat-card animate-in animate-in-${i + 1}`}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <div>
                                    <div className="stat-card-label">{s.label}</div>
                                    <div className="stat-card-value">{s.value}</div>
                                </div>
                                <div className={`stat-card-icon ${s.cls}`}>{s.icon}</div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Toolbar */}
            <div className="vz-card mb-3 animate-in animate-in-5">
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '0.75rem' }}>
                        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                            <div style={{ position: 'relative' }}>
                                <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                                <input
                                    className="vz-form-control"
                                    placeholder="Search bookings..."
                                    value={search}
                                    onChange={(e) => { setSearch(e.target.value); setCurrentPage(1); }}
                                    style={{ paddingLeft: '2.25rem', width: 220 }}
                                />
                            </div>
                            <select
                                className="vz-form-control"
                                value={statusFilter}
                                onChange={(e) => { setStatusFilter(e.target.value); setCurrentPage(1); }}
                                style={{ width: 140 }}
                            >
                                <option value="all">All Status</option>
                                <option value="Confirmed">Confirmed</option>
                                <option value="Pending">Pending</option>
                                <option value="Cancelled">Cancelled</option>
                            </select>
                        </div>
                        <div style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)' }}>
                            Total Revenue: <span style={{ fontWeight: 700, color: 'var(--vz-success)' }}>₹{totalRevenue.toLocaleString()}</span>
                        </div>
                    </div>
                </div>
            </div>

            {/* Table */}
            <div className="vz-card animate-in animate-in-6">
                <div className="vz-card-body" style={{ padding: 0 }}>
                    <div className="vz-table-wrapper">
                        <table className="vz-table">
                            <thead>
                                <tr>
                                    <th>Booking ID</th>
                                    <th>User</th>
                                    <th>Venue</th>
                                    <th>Date & Time</th>
                                    <th>Guests</th>
                                    <th>Amount</th>
                                    <th>Status</th>
                                </tr>
                            </thead>
                            <tbody>
                                {paged.map((booking) => (
                                    <tr key={booking.id}>
                                        <td style={{ fontWeight: 600, color: 'var(--vz-primary)' }}>{booking.id}</td>
                                        <td style={{ fontWeight: 500 }}>{booking.user}</td>
                                        <td style={{ color: 'var(--vz-text-muted)' }}>{booking.venue}</td>
                                        <td style={{ color: 'var(--vz-text-muted)' }}>
                                            {new Date(booking.date).toLocaleDateString('en-IN', { month: 'short', day: 'numeric' })} · {booking.time}
                                        </td>
                                        <td>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                                                <BiGroup style={{ color: 'var(--vz-text-muted)' }} /> {booking.guests}
                                            </div>
                                        </td>
                                        <td style={{ fontWeight: 600 }}>₹{booking.amount.toLocaleString()}</td>
                                        <td><span className={`vz-badge ${getStatusBadge(booking.status)}`}>{booking.status}</span></td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Bookings;
