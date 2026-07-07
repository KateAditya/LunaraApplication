import React, { useState, useEffect } from 'react';
import { BiSearch, BiPlus, BiEdit, BiBlock, BiShow, BiLoaderAlt } from 'react-icons/bi';
// Mock data removed
import { UserForm } from '../components/UserForm';
import { UserDetails } from '../components/UserDetails';
import { usersApi } from '../api/users';
import type { User } from '../types/user';
import toast from 'react-hot-toast';

const getStatusBadge = (user: User) => {
    if (!user.isActive) return 'danger';
    if (!user.isVerified) return 'warning';
    return 'success';
};

const getStatusText = (user: User) => {
    if (!user.isActive) return 'Inactive / Banned';
    if (!user.isVerified) return 'Pending Verification';
    return 'Active';
};

export const Users: React.FC = () => {
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState('all');
    const [currentPage, setCurrentPage] = useState(1);
    const perPage = 10;

    // API Data state
    const [users, setUsers] = useState<User[]>([]);
    const [loading, setLoading] = useState(true);
    const [totalUsers, setTotalUsers] = useState(0);
    const [totalPages, setTotalPages] = useState(1);

    // CRUD modal state
    const [showForm, setShowForm] = useState(false);
    const [showDetails, setShowDetails] = useState(false);
    const [selectedUser, setSelectedUser] = useState<User | null>(null);

    const loadUsers = async () => {
        try {
            setLoading(true);
            const response = await usersApi.getUsers({
                page: currentPage,
                limit: perPage,
                search: search || undefined,
                isActive: statusFilter === 'all' ? undefined : statusFilter === 'active',
                // For 'inactive', we can assume isActive=false, but 'banned' is harder to map directly if not standard. 
                // We'll manage strictly isActive for now.
            });

            if (response.success) {
                // Adjust if backend returns { count, users, totalPages } vs { data: { users, pagination } }
                // Based on backend implementation: { count, users, totalPages }
                const resData = response as any;
                if (resData.users) {
                    setUsers(resData.users);
                    setTotalUsers(resData.count || 0);
                    setTotalPages(resData.totalPages || 1);
                } else if (resData.data?.users) {
                    setUsers(resData.data.users);
                    setTotalUsers(resData.data.pagination?.total || 0);
                    setTotalPages(resData.data.pagination?.totalPages || 1);
                }
            } else {
                toast.error('Failed to load users');
            }
        } catch (error) {
            console.error('Error loading users:', error);
            toast.error('Failed to load users');
        } finally {
            setLoading(false);
        }
    };

    // Debounce search
    useEffect(() => {
        const timer = setTimeout(() => {
            loadUsers();
        }, 300);
        return () => clearTimeout(timer);
    }, [currentPage, search, statusFilter]);

    const handleView = (user: User) => { setSelectedUser(user); setShowDetails(true); };
    const handleAdd = () => { setSelectedUser(null); setShowForm(true); };
    const handleEdit = (user: User) => { setSelectedUser(user); setShowForm(true); };

    const handleDelete = async (user: User) => {
        if (window.confirm(`Are you sure you want to delete "${user.firstName} ${user.lastName}"? This action cannot be undone.`)) {
            try {
                const res = await usersApi.deleteUser(user.id);
                if (res.success) {
                    toast.success(`User "${user.firstName} ${user.lastName}" deleted`);
                    loadUsers();
                } else {
                    toast.error(res.message || 'Failed to delete user');
                }
            } catch (error) {
                console.error('Delete error:', error);
                toast.error('Failed to delete user');
            }
        }
    };

    const handleSave = async (data: any) => {
        try {
            if (selectedUser) {
                const res = await usersApi.updateUser(selectedUser.id, {
                    ...data,
                });
                if (res.success) {
                    toast.success('User updated successfully');
                    setShowForm(false);
                    setSelectedUser(null);
                    loadUsers();
                }
            } else {
                const res = await usersApi.createUser(data);
                if (res.success) {
                    toast.success('User added successfully');
                    setShowForm(false);
                    setSelectedUser(null);
                    loadUsers();
                }
            }
        } catch (error) {
            console.error('Save error:', error);
            toast.error('Failed to save user');
        }
    };

    return (
        <div>
            {/* Toolbar */}
            <div className="vz-card mb-3 animate-in animate-in-1">
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '0.75rem' }}>
                        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                            <div style={{ position: 'relative' }}>
                                <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                                <input
                                    className="vz-form-control"
                                    placeholder="Search users..."
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
                                <option value="active">Active</option>
                                <option value="inactive">Inactive</option>
                                <option value="banned">Banned</option>
                            </select>
                        </div>
                        <button className="vz-btn vz-btn-primary" onClick={handleAdd}>
                            <BiPlus /> Add User
                        </button>
                    </div>
                </div>
            </div>

            {/* Table */}
            <div className="vz-card animate-in animate-in-2">
                <div className="vz-card-body" style={{ padding: 0 }}>
                    <div className="vz-table-wrapper">
                        <table className="vz-table">
                            <thead>
                                <tr>
                                    <th style={{ width: 50 }}>#</th>
                                    <th>User</th>
                                    <th>Email</th>
                                    <th>Phone</th>
                                    <th>Status</th>
                                    <th>Blocks</th>
                                    <th>Role</th>
                                    <th style={{ width: 80 }}>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {loading ? (
                                    <tr>
                                        <td colSpan={8} style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>
                                            <BiLoaderAlt className="vz-spin" style={{ fontSize: '1.5rem', marginBottom: '0.5rem', color: 'var(--vz-primary)' }} />
                                            <div>Loading users...</div>
                                        </td>
                                    </tr>
                                ) : users.length === 0 ? (
                                    <tr>
                                        <td colSpan={8} style={{ textAlign: 'center', padding: '2rem', color: 'var(--vz-text-muted)' }}>
                                            No users found
                                        </td>
                                    </tr>
                                ) : (
                                    users.map((user: User, idx: number) => (
                                        <tr key={user.id || idx}>
                                            <td style={{ color: 'var(--vz-text-muted)' }}>
                                                {(currentPage - 1) * perPage + idx + 1}
                                            </td>
                                            <td>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                                                    <div style={{
                                                        width: 32,
                                                        height: 32,
                                                        borderRadius: '50%',
                                                        background: `linear-gradient(135deg, var(--vz-primary), var(--vz-pink))`,
                                                        display: 'flex',
                                                        alignItems: 'center',
                                                        justifyContent: 'center',
                                                        color: '#fff',
                                                        fontWeight: 600,
                                                        fontSize: '0.6875rem',
                                                        flexShrink: 0,
                                                    }}>
                                                        {user.firstName?.charAt(0)}{user.lastName?.charAt(0)}
                                                    </div>
                                                    <div>
                                                        <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>{user.firstName} {user.lastName}</div>
                                                        <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                                                            Joined {user.createdAt ? new Date(user.createdAt).toLocaleDateString() : 'N/A'}
                                                        </div>
                                                    </div>
                                                </div>
                                            </td>
                                            <td style={{ color: 'var(--vz-text-muted)' }}>{user.email}</td>
                                            <td style={{ color: 'var(--vz-text-muted)' }}>{user.phone || '—'}</td>
                                            <td>
                                                <span className={`vz-badge ${getStatusBadge(user)}`}>
                                                    {getStatusText(user)}
                                                </span>
                                            </td>
                                            <td>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
                                                    <span style={{ fontWeight: 600 }}>{user.blockCount ?? 0}</span>
                                                    {user.isAutoblocked && (
                                                        <span style={{
                                                            fontSize: '0.625rem',
                                                            background: 'rgba(230, 83, 60, 0.1)',
                                                            color: 'rgb(230, 83, 60)',
                                                            padding: '2px 6px',
                                                            borderRadius: '4px',
                                                            fontWeight: 600
                                                        }}>Autoblocked</span>
                                                    )}
                                                </div>
                                            </td>
                                            <td style={{ color: 'var(--vz-text-muted)' }}>{user.role || 'User'}</td>
                                            <td>
                                                <div style={{ display: 'flex', gap: '0.25rem' }}>
                                                    <button className="vz-btn-icon" title="View" onClick={() => handleView(user)}><BiShow /></button>
                                                    <button className="vz-btn-icon" title="Edit" onClick={() => handleEdit(user)}><BiEdit /></button>
                                                    <button className="vz-btn-icon" title="Delete" style={{ color: 'var(--vz-danger)' }} onClick={() => handleDelete(user)}><BiBlock /></button>
                                                </div>
                                            </td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Pagination */}
                {totalPages > 1 && (
                    <div style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        padding: '0.75rem 1.25rem',
                        borderTop: '1px solid var(--vz-border-color)',
                    }}>
                        <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                            Showing {(currentPage - 1) * perPage + 1}–{Math.min(currentPage * perPage, totalUsers)} of {totalUsers}
                        </span>
                        <div style={{ display: 'flex', gap: '0.25rem' }}>
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                disabled={currentPage === 1}
                                onClick={() => setCurrentPage(p => p - 1)}
                            >Prev</button>
                            {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => i + 1).map(p => (
                                <button
                                    key={p}
                                    className={`vz-btn vz-btn-sm ${p === currentPage ? 'vz-btn-primary' : 'vz-btn-outline'}`}
                                    onClick={() => setCurrentPage(p)}
                                >{p}</button>
                            ))}
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                disabled={currentPage === totalPages}
                                onClick={() => setCurrentPage(p => p + 1)}
                            >Next</button>
                        </div>
                    </div>
                )}
            </div>

            {/* CRUD Modals */}
            {showForm && (
                <UserForm
                    user={selectedUser}
                    onClose={() => { setShowForm(false); setSelectedUser(null); }}
                    onSave={handleSave}
                />
            )}
            {showDetails && selectedUser && (
                <UserDetails
                    user={selectedUser}
                    onClose={() => { setShowDetails(false); setSelectedUser(null); }}
                />
            )}
        </div>
    );
};

export default Users;
