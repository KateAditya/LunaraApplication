import { useState, type FormEvent } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getEventBookings } from '../../api/eventBookings';
import { Card, Table, Badge, Form, Row, Col, Button, Spinner, Pagination } from 'react-bootstrap';
import { format } from 'date-fns';
import { useThemeMode } from '../../context/ThemeContext';
import { EventBookingDetailModal } from './EventBookingDetailModal';
import { BiSearch, BiCalendar } from 'react-icons/bi';

const safeFormat = (d: any, pattern: string, fallback = '—') => {
  if (!d) return fallback;
  try {
    const parsed = new Date(d);
    if (isNaN(parsed.getTime())) return fallback;
    return format(parsed, pattern);
  } catch (_) {
    return fallback;
  }
};

interface EventBookingTableProps {
  eventId: string;
  event?: any;
}

export function EventBookingTable({ eventId, event }: EventBookingTableProps) {
  const { mode } = useThemeMode();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [bookingStatus, setBookingStatus] = useState('all');
  const [paymentStatus, setPaymentStatus] = useState('all');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  const [selectedBooking, setSelectedBooking] = useState<any>(null);
  
  // debounced search state
  const [debouncedSearch, setDebouncedSearch] = useState('');

  const handleSearch = (e: FormEvent) => {
    e.preventDefault();
    setDebouncedSearch(search);
    setPage(1);
  };

  const handleReset = () => {
    setSearch('');
    setDebouncedSearch('');
    setBookingStatus('all');
    setPaymentStatus('all');
    setFromDate('');
    setToDate('');
    setPage(1);
  };

  const isAllEvents = !eventId || eventId === 'all';

  const { data, isLoading, isError } = useQuery({
    queryKey: ['eventBookings', eventId, page, debouncedSearch, bookingStatus, paymentStatus, fromDate, toDate],
    queryFn: () => getEventBookings(eventId, {
      page,
      limit: 20,
      search: debouncedSearch,
      bookingStatus: bookingStatus !== 'all' ? bookingStatus : undefined,
      paymentStatus: paymentStatus !== 'all' ? paymentStatus : undefined,
      fromDate: fromDate || undefined,
      toDate: toDate || undefined,
    }),
  });

  const getStatusBadge = (status: string) => {
    switch (status?.toLowerCase()) {
      case 'confirmed': return 'bg-success-subtle text-success';
      case 'completed': return 'bg-primary-subtle text-primary';
      case 'pending': return 'bg-warning-subtle text-warning';
      case 'cancelled': return 'bg-danger-subtle text-danger';
      case 'failed': return 'bg-danger-subtle text-danger';
      default: return 'bg-secondary-subtle text-secondary';
    }
  };

  const getPaymentBadge = (status: string, amount: number) => {
    if (amount === 0) {
      return <Badge bg="success">FREE</Badge>;
    }
    switch (status?.toLowerCase()) {
      case 'paid': return <Badge bg="success">PAID</Badge>;
      case 'pending': return <Badge bg="warning" className="text-dark">PENDING</Badge>;
      case 'failed': return <Badge bg="danger">FAILED</Badge>;
      case 'refunded': return <Badge bg="info">REFUNDED</Badge>;
      default: return <Badge bg="secondary">{(status || 'UNPAID').toUpperCase()}</Badge>;
    }
  };

  const cardBg = mode === 'dark' ? 'bg-dark text-white border-secondary' : 'bg-white text-dark shadow-sm border-0';
  const tableClass = mode === 'dark' ? 'table-dark' : '';

  return (
    <Card className={cardBg} style={{ borderRadius: '14px' }}>
      <Card.Header className="bg-transparent border-0 pt-3 pb-2">
        <div className="d-flex justify-content-between align-items-center flex-wrap gap-2">
          <div>
            <h5 className="fw-bold mb-0">Event Bookings & Registrations</h5>
            <p className="text-muted small mb-0">
              {isAllEvents ? 'Showing all party event bookings across the platform' : `Bookings for ${event?.title || 'this event'}`}
            </p>
          </div>
        </div>
      </Card.Header>

      <Card.Body>
        <Form onSubmit={handleSearch} className="mb-4">
          <Row className="g-2 align-items-end">
            <Col xl={3} lg={4} md={6} xs={12}>
              <Form.Label className="small fw-semibold text-muted mb-1">Search Customer / Booking</Form.Label>
              <div className="input-group input-group-sm">
                <span className="input-group-text bg-light border-end-0">
                  <BiSearch className="text-muted" />
                </span>
                <Form.Control
                  type="text"
                  placeholder="Booking ID, Name, Phone, Email…"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className={`border-start-0 ${mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}`}
                />
              </div>
            </Col>

            <Col xl={2} lg={2} md={3} xs={6}>
              <Form.Label className="small fw-semibold text-muted mb-1">Booking Status</Form.Label>
              <Form.Select 
                value={bookingStatus}
                onChange={(e) => { setBookingStatus(e.target.value); setPage(1); }}
                className={`form-select-sm ${mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}`}
              >
                <option value="all">All Bookings</option>
                <option value="confirmed">Confirmed</option>
                <option value="completed">Completed</option>
                <option value="pending">Pending</option>
                <option value="cancelled">Cancelled</option>
              </Form.Select>
            </Col>

            <Col xl={2} lg={2} md={3} xs={6}>
              <Form.Label className="small fw-semibold text-muted mb-1">Payment Status</Form.Label>
              <Form.Select 
                value={paymentStatus}
                onChange={(e) => { setPaymentStatus(e.target.value); setPage(1); }}
                className={`form-select-sm ${mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}`}
              >
                <option value="all">All Payments</option>
                <option value="paid">Paid</option>
                <option value="refunded">Refunded</option>
                <option value="pending">Pending</option>
                <option value="free">Free</option>
                <option value="failed">Failed</option>
              </Form.Select>
            </Col>

            <Col xl={2} lg={2} md={3} xs={6}>
              <Form.Label className="small fw-semibold text-muted mb-1">From Date</Form.Label>
              <Form.Control 
                type="date"
                size="sm"
                value={fromDate}
                onChange={(e) => { setFromDate(e.target.value); setPage(1); }}
                className={mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}
              />
            </Col>

            <Col xl={2} lg={2} md={3} xs={6}>
              <Form.Label className="small fw-semibold text-muted mb-1">To Date</Form.Label>
              <Form.Control 
                type="date"
                size="sm"
                value={toDate}
                onChange={(e) => { setToDate(e.target.value); setPage(1); }}
                className={mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}
              />
            </Col>

            <Col xl={1} lg={2} md={3} xs={12} className="d-flex gap-1">
              <Button type="submit" variant="primary" size="sm" className="w-100 fw-semibold">
                Filter
              </Button>
              <Button type="button" variant="outline-secondary" size="sm" onClick={handleReset} title="Reset filters">
                Reset
              </Button>
            </Col>
          </Row>
        </Form>

        {isLoading ? (
          <div className="text-center py-5">
            <Spinner animation="border" variant="primary" />
            <div className="text-muted small mt-2">Loading event bookings...</div>
          </div>
        ) : isError ? (
          <div className="text-center py-5 text-danger">
            Failed to load bookings. Please try again.
          </div>
        ) : data?.bookings?.length === 0 ? (
          <div className="text-center py-5 text-muted">
            <BiCalendar size={42} className="opacity-25 mb-2" />
            <div>No party event bookings found matching your filters.</div>
          </div>
        ) : (
          <div className="table-responsive">
            <Table hover className={`${tableClass} align-middle small mb-0`}>
              <thead className="table-light">
                <tr>
                  <th className="px-3">Booking ID</th>
                  {isAllEvents && <th>Party Event</th>}
                  <th>Customer</th>
                  <th>Date & Time</th>
                  <th>Guests</th>
                  <th>Total Paid</th>
                  <th>Payment</th>
                  <th>Booking Status</th>
                  <th className="text-center">Action</th>
                </tr>
              </thead>
              <tbody>
                {data.bookings.map((booking: any) => {
                  const eventInfo = booking.partyEvent || event;
                  const isCancelled = booking.status === 'cancelled';
                  const userPhone = booking.user?.phone || booking.user?.mobile || booking.mobileNumber || '—';

                  return (
                    <tr key={booking.id}>
                      <td className="px-3">
                        <span className="fw-bold font-monospace text-primary" style={{ fontSize: '0.78rem' }}>
                          {booking.bookingNumber}
                        </span>
                        {booking.ticket?.ticketNumber && (
                          <div className="text-muted font-monospace" style={{ fontSize: '0.7rem' }}>
                            Ticket: {booking.ticket.ticketNumber}
                          </div>
                        )}
                      </td>

                      {isAllEvents && (
                        <td>
                          <div className="fw-semibold text-truncate" style={{ maxWidth: 180 }}>
                            {eventInfo?.title || 'Party Event'}
                          </div>
                          <div className="text-muted" style={{ fontSize: '0.72rem' }}>
                            {eventInfo?.city || eventInfo?.area || 'Venue Event'}
                          </div>
                        </td>
                      )}

                      <td>
                        {booking.user ? (
                          <div>
                            <div className="fw-semibold">
                              {booking.user.firstName || ''} {booking.user.lastName || ''}
                            </div>
                            <div className="text-muted" style={{ fontSize: '0.72rem' }}>{userPhone}</div>
                            <div className="text-muted" style={{ fontSize: '0.72rem' }}>{booking.user.email}</div>
                          </div>
                        ) : (
                          <div>
                            <div className="fw-semibold">Guest Booking</div>
                            <div className="text-muted" style={{ fontSize: '0.72rem' }}>{userPhone}</div>
                          </div>
                        )}
                      </td>

                      <td>
                        <div style={{ fontSize: '0.75rem' }}>
                          {safeFormat(booking.createdAt, 'dd MMM yyyy, HH:mm')}
                        </div>
                      </td>

                      <td>
                        <span className="badge bg-light text-dark border">
                          {booking.numberOfGuests || 1} {booking.numberOfGuests === 1 ? 'Guest' : 'Guests'}
                        </span>
                      </td>

                      <td>
                        <div className={`fw-bold ${isCancelled ? 'text-danger' : 'text-success'}`}>
                          ₹{booking.totalAmount || 0}
                        </div>
                        {isCancelled && booking.cancellationReason && (
                          <div className="text-muted small text-truncate" style={{ maxWidth: 140, fontSize: '0.7rem' }}>
                            {booking.cancellationReason}
                          </div>
                        )}
                      </td>

                      <td>{getPaymentBadge(booking.paymentStatus, Number(booking.totalAmount))}</td>

                      <td>
                        <span className={`badge rounded-pill ${getStatusBadge(booking.status)}`}>
                          {(booking.status || 'PENDING').toUpperCase()}
                        </span>
                      </td>

                      <td className="text-center">
                        <Button 
                          variant="outline-primary" 
                          size="sm"
                          onClick={() => setSelectedBooking(booking)}
                          className="px-2 py-0 fw-semibold"
                          style={{ fontSize: '0.75rem' }}
                        >
                          View
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </Table>
          </div>
        )}

        {/* Pagination */}
        {data && data.totalPages > 1 && (
          <div className="d-flex justify-content-between align-items-center mt-3 pt-2 border-top">
            <div className="text-muted small">
              Showing {(page - 1) * 20 + 1}–{Math.min(page * 20, data.totalCount)} of {data.totalCount} bookings
            </div>
            <Pagination size="sm" className="mb-0">
              <Pagination.Prev 
                disabled={page <= 1} 
                onClick={() => setPage(p => p - 1)} 
              />
              {Array.from({ length: Math.min(5, data.totalPages) }, (_, i) => {
                const p = Math.max(1, Math.min(data.totalPages - 4, page - 2)) + i;
                return (
                  <Pagination.Item 
                    key={p} 
                    active={p === page} 
                    onClick={() => setPage(p)}
                  >
                    {p}
                  </Pagination.Item>
                );
              })}
              <Pagination.Next 
                disabled={page >= data.totalPages} 
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
          event={selectedBooking.partyEvent || event}
        />
      )}
    </Card>
  );
}

export default EventBookingTable;
