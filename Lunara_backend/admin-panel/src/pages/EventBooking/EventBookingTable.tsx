import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getEventBookings } from '../../api/eventBookings';
import { Card, Table, Badge, Form, Row, Col, Button, Spinner, Pagination } from 'react-bootstrap';
import { format } from 'date-fns';
import { useThemeMode } from '../../context/ThemeContext';
import { EventBookingDetailModal } from './EventBookingDetailModal';
import { Search } from 'lucide-react';

interface EventBookingTableProps {
  eventId: string;
  event: any;
}

export function EventBookingTable({ eventId, event }: EventBookingTableProps) {
  const { mode } = useThemeMode();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [bookingStatus, setBookingStatus] = useState('');
  const [paymentStatus, setPaymentStatus] = useState('');
  const [selectedBooking, setSelectedBooking] = useState<any>(null);
  
  // debounced search state
  const [debouncedSearch, setDebouncedSearch] = useState('');

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setDebouncedSearch(search);
    setPage(1);
  };

  const { data, isLoading, isError } = useQuery({
    queryKey: ['eventBookings', eventId, page, debouncedSearch, bookingStatus, paymentStatus],
    queryFn: () => getEventBookings(eventId, {
      page,
      limit: 20,
      search: debouncedSearch,
      bookingStatus,
      paymentStatus
    }),
    enabled: !!eventId,
  });

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'confirmed': return 'success';
      case 'pending': return 'warning';
      case 'cancelled': return 'danger';
      case 'failed': return 'danger';
      case 'completed': return 'info';
      default: return 'secondary';
    }
  };

  const getPaymentBadge = (status: string, amount: number) => {
    if (amount === 0 && (status === 'paid' || status === 'pending' || status === 'confirmed')) {
      return <Badge bg="success">FREE</Badge>;
    }
    switch (status) {
      case 'paid': return <Badge bg="success">PAID</Badge>;
      case 'pending': return <Badge bg="warning">PENDING</Badge>;
      case 'failed': return <Badge bg="danger">FAILED</Badge>;
      case 'refunded': return <Badge bg="info">REFUNDED</Badge>;
      default: return <Badge bg="secondary">{status.toUpperCase()}</Badge>;
    }
  };

  const cardBg = mode === 'dark' ? 'bg-dark text-white border-secondary' : 'bg-white text-dark';
  const tableClass = mode === 'dark' ? 'table-dark' : '';

  return (
    <Card className={cardBg}>
      <Card.Body>
        <Form onSubmit={handleSearch} className="mb-4">
          <Row className="g-3">
            <Col md={4}>
              <div className="d-flex">
                <Form.Control
                  type="text"
                  placeholder="Search Booking ID, Name, Mobile, Email..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className={mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}
                />
                <Button type="submit" variant="primary" className="ms-2">
                  <Search size={18} />
                </Button>
              </div>
            </Col>
            <Col md={3}>
              <Form.Select 
                value={bookingStatus}
                onChange={(e) => { setBookingStatus(e.target.value); setPage(1); }}
                className={mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}
              >
                <option value="">All Booking Statuses</option>
                <option value="confirmed">Confirmed</option>
                <option value="pending">Pending</option>
                <option value="cancelled">Cancelled</option>
              </Form.Select>
            </Col>
            <Col md={3}>
              <Form.Select 
                value={paymentStatus}
                onChange={(e) => { setPaymentStatus(e.target.value); setPage(1); }}
                className={mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}
              >
                <option value="">All Payment Statuses</option>
                <option value="paid">Paid</option>
                <option value="pending">Pending</option>
                <option value="free">Free</option>
                <option value="failed">Failed</option>
                <option value="refunded">Refunded</option>
              </Form.Select>
            </Col>
          </Row>
        </Form>

        {isLoading ? (
          <div className="text-center py-5"><Spinner animation="border" /></div>
        ) : isError ? (
          <div className="text-center py-5 text-danger">Failed to load bookings.</div>
        ) : data?.bookings?.length === 0 ? (
          <div className="text-center py-5 text-muted">No bookings found for this event.</div>
        ) : (
          <div className="table-responsive">
            <Table hover className={`${tableClass} align-middle`}>
              <thead>
                <tr>
                  <th>Booking ID</th>
                  <th>User Details</th>
                  <th>Booking Date</th>
                  <th>Quantity</th>
                  <th>Entry Price</th>
                  <th>Total Amount</th>
                  <th>Payment Status</th>
                  <th>Booking Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.bookings.map((booking: any) => (
                  <tr key={booking.id}>
                    <td><strong>{booking.bookingNumber}</strong></td>
                    <td>
                      {booking.user ? (
                        <>
                          <div>{booking.user.firstName} {booking.user.lastName}</div>
                          <div className="text-muted small">{booking.user.mobile}</div>
                          <div className="text-muted small">{booking.user.email}</div>
                        </>
                      ) : (
                        <span className="text-muted">User Data Missing</span>
                      )}
                    </td>
                    <td>{format(new Date(booking.createdAt), 'dd-MM-yyyy HH:mm')}</td>
                    <td>{booking.numberOfGuests}</td>
                    <td>₹{event.entryPrice || 0}</td>
                    <td><strong>₹{booking.totalAmount}</strong></td>
                    <td>{getPaymentBadge(booking.paymentStatus, Number(booking.totalAmount))}</td>
                    <td>
                      <Badge bg={getStatusBadge(booking.status)}>
                        {booking.status.toUpperCase()}
                      </Badge>
                    </td>
                    <td>
                      <Button 
                        variant="outline-primary" 
                        size="sm"
                        onClick={() => setSelectedBooking(booking)}
                      >
                        View
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </Table>
          </div>
        )}

        {/* Pagination */}
        {data && data.totalPages > 1 && (
          <div className="d-flex justify-content-between align-items-center mt-3">
            <div className="text-muted small">
              Showing {(page - 1) * 20 + 1}–{Math.min(page * 20, data.totalCount)} of {data.totalCount} bookings
            </div>
            <Pagination className="mb-0">
              <Pagination.Prev 
                disabled={page === 1} 
                onClick={() => setPage(p => p - 1)} 
              />
              <Pagination.Item active>{page}</Pagination.Item>
              <Pagination.Next 
                disabled={page === data.totalPages} 
                onClick={() => setPage(p => p + 1)} 
              />
            </Pagination>
          </div>
        )}
      </Card.Body>

      {selectedBooking && (
        <EventBookingDetailModal 
          show={true}
          onHide={() => setSelectedBooking(null)}
          booking={selectedBooking}
          event={event}
        />
      )}
    </Card>
  );
}
