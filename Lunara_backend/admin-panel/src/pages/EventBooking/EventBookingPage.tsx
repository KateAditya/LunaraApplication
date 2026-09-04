import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getPartyEvents, getEventSummary } from '../../api/eventBookings';
import { Container, Row, Col, Card, Form, Spinner, ProgressBar } from 'react-bootstrap';
import { format } from 'date-fns';
import { EventBookingTable } from './EventBookingTable';

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
import {
  BiCalendarEvent,
  BiGroup,
  BiDollarCircle,
  BiMap,
  BiCheckCircle,
  BiXCircle,
  BiRefresh,
  BiMoney,
  BiTrendingUp,
  BiUndo,
  BiParty,
} from 'react-icons/bi';
import { useThemeMode } from '../../context/ThemeContext';

export function EventBookingPage() {
  const { mode } = useThemeMode();
  const [selectedEventId, setSelectedEventId] = useState<string>('all');

  const { data: eventsData, isLoading: loadingEvents, refetch: refetchEvents } = useQuery({
    queryKey: ['partyEvents'],
    queryFn: getPartyEvents,
  });

  const { data: summaryData, isLoading: loadingSummary, refetch: refetchSummary } = useQuery({
    queryKey: ['eventSummary', selectedEventId],
    queryFn: () => getEventSummary(selectedEventId),
  });

  const events = eventsData?.events || [];
  const selectedEvent = selectedEventId !== 'all' ? events.find((e: any) => e.id === selectedEventId) : null;
  const summary = summaryData?.summary;

  const cardBg = mode === 'dark' ? 'bg-dark text-white border-secondary' : 'bg-white text-dark shadow-sm border-0';

  const handleRefreshAll = () => {
    refetchEvents();
    refetchSummary();
  };

  return (
    <Container fluid className="py-4">
      {/* ─── Hero Header Banner ────────────────────────────────────────────── */}
      <div
        className="card border-0 shadow-sm mb-4"
        style={{
          background: 'linear-gradient(135deg, #1e1b4b 0%, #312e81 50%, #4338ca 100%)',
          borderRadius: '16px',
        }}
      >
        <div className="card-body p-4 text-white">
          <div className="d-flex flex-column flex-md-row justify-content-between align-items-md-center gap-3">
            <div>
              <div className="d-flex align-items-center gap-2 mb-1">
                <span className="p-2 rounded-3 bg-white bg-opacity-10 text-white">
                  <BiParty size={26} />
                </span>
                <h4 className="fw-bold mb-0 text-white">Party Event Booking & Revenue Hub</h4>
              </div>
              <p className="mb-0 text-white-50 small">
                Track real-time event registrations, ticket sales revenue, cancellations, refund statistics, and guest attendances.
              </p>
            </div>
            <div className="d-flex align-items-center gap-2">
              <button
                onClick={handleRefreshAll}
                className="btn btn-outline-light btn-sm d-flex align-items-center gap-1"
                title="Refresh Metrics"
              >
                <BiRefresh size={16} /> Refresh
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* ─── Event Selector Card ─────────────────────────────────────────── */}
      <Card className={`mb-4 ${cardBg}`} style={{ borderRadius: '14px' }}>
        <Card.Body className="p-3">
          <Row className="align-items-center g-3">
            <Col md={6} lg={5}>
              <Form.Label className="small fw-bold text-muted text-uppercase mb-1">
                Filter by Party Event
              </Form.Label>
              {loadingEvents ? (
                <div className="py-1 text-muted small">
                  <Spinner animation="border" size="sm" className="me-2" /> Loading party events...
                </div>
              ) : (
                <Form.Select
                  value={selectedEventId}
                  onChange={(e) => setSelectedEventId(e.target.value)}
                  className={`form-select-sm fw-semibold ${mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}`}
                >
                  <option value="all">🌟 All Party Events (Platform-wide Overview)</option>
                  {events.map((evt: any) => (
                    <option key={evt.id} value={evt.id}>
                      {evt.title} ({safeFormat(evt.eventDate, 'dd MMM yyyy', 'No date')}) • {evt.city || 'General'}
                    </option>
                  ))}
                </Form.Select>
              )}
            </Col>
            <Col md={6} lg={7} className="d-flex justify-content-md-end align-items-center">
              <div className="text-muted small">
                {selectedEventId === 'all' ? (
                  <span>Showing aggregated statistics for <strong>{events.length}</strong> active & scheduled events</span>
                ) : (
                  <span>Viewing focused metrics for selected event</span>
                )}
              </div>
            </Col>
          </Row>
        </Card.Body>
      </Card>

      {/* ─── Selected Event Info (if specific event chosen) ────────────────── */}
      {selectedEvent && (
        <Card className={`mb-4 ${cardBg}`} style={{ borderRadius: '14px' }}>
          <Card.Body className="p-4">
            <div className="d-flex justify-content-between align-items-start mb-3 flex-wrap gap-2">
              <div>
                <span className="badge bg-primary-subtle text-primary mb-2 text-uppercase fw-semibold" style={{ fontSize: '0.7rem' }}>
                  Selected Event Details
                </span>
                <h4 className="fw-bold mb-1">{selectedEvent.title}</h4>
              </div>
              <div className="text-end">
                <span className="badge bg-success-subtle text-success fs-6 fw-bold">
                  Entry: ₹{selectedEvent.entryPrice || 0}
                </span>
              </div>
            </div>

            <Row className="g-3">
              <Col sm={6} md={3}>
                <div className="p-2 rounded bg-light bg-opacity-50">
                  <div className="text-muted small d-flex align-items-center gap-1 mb-1">
                    <BiCalendarEvent className="text-primary" /> Event Date
                  </div>
                  <strong>{safeFormat(selectedEvent.eventDate, 'dd-MM-yyyy')}</strong>
                </div>
              </Col>
              <Col sm={6} md={3}>
                <div className="p-2 rounded bg-light bg-opacity-50">
                  <div className="text-muted small d-flex align-items-center gap-1 mb-1">
                    <BiMap className="text-danger" /> Venue & City
                  </div>
                  <strong>{selectedEvent.venue?.name || selectedEvent.area || 'Venue TBA'}, {selectedEvent.city}</strong>
                </div>
              </Col>
              <Col sm={6} md={3}>
                <div className="p-2 rounded bg-light bg-opacity-50">
                  <div className="text-muted small d-flex align-items-center gap-1 mb-1">
                    <BiGroup className="text-info" /> Capacity / Limit
                  </div>
                  <strong>{selectedEvent.isUnlimited ? 'Unlimited Seats' : `${selectedEvent.seatLimit} Seats`}</strong>
                </div>
              </Col>
              <Col sm={6} md={3}>
                <div className="p-2 rounded bg-light bg-opacity-50">
                  <div className="text-muted small d-flex align-items-center gap-1 mb-1">
                    <BiTrendingUp className="text-success" /> Occupancy Rate
                  </div>
                  <strong>{summary?.occupancyRate ? `${summary.occupancyRate}%` : '—'}</strong>
                </div>
              </Col>
            </Row>

            {summary && !selectedEvent.isUnlimited && (
              <div className="mt-3">
                <div className="d-flex justify-content-between small text-muted mb-1">
                  <span>Capacity Filled: {summary.filledSeats} / {selectedEvent.seatLimit}</span>
                  <span>{summary.remainingSeats} remaining</span>
                </div>
                <ProgressBar
                  now={summary.occupancyRate || 0}
                  variant={summary.occupancyRate > 85 ? 'danger' : summary.occupancyRate > 50 ? 'warning' : 'success'}
                  style={{ height: '8px' }}
                />
              </div>
            )}
          </Card.Body>
        </Card>
      )}

      {/* ─── Financial & Operational KPI Grid ─────────────────────────────── */}
      {loadingSummary ? (
        <div className="text-center py-5">
          <Spinner animation="border" variant="primary" />
          <p className="text-muted small mt-2">Computing event revenue & cancellation analysis...</p>
        </div>
      ) : summary ? (
        <Row className="g-3 mb-4">
          {/* Gross Revenue */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Gross Ticket Revenue</span>
                  <span className="p-2 rounded bg-success-subtle text-success">
                    <BiMoney size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-success">₹{(summary.grossRevenue || 0).toLocaleString('en-IN')}</h3>
                <span className="text-muted small">Total confirmed ticket sales</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Refunded on Cancellations */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Total Refunded</span>
                  <span className="p-2 rounded bg-danger-subtle text-danger">
                    <BiUndo size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-danger">₹{(summary.refundedAmount || 0).toLocaleString('en-IN')}</h3>
                <span className="text-muted small">{summary.cancelledBookings || 0} cancelled bookings refunded</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Net Revenue */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Net Retained Revenue</span>
                  <span className="p-2 rounded bg-primary-subtle text-primary">
                    <BiDollarCircle size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-primary">₹{(summary.netRevenue || 0).toLocaleString('en-IN')}</h3>
                <span className="text-muted small">Gross sales minus refunded cancellations</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Total Attendees */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Total Attendees</span>
                  <span className="p-2 rounded bg-info-subtle text-info">
                    <BiGroup size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-info">{(summary.totalAttendees || 0).toLocaleString('en-IN')}</h3>
                <span className="text-muted small">Registered guests / entries</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Total Bookings */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Total Bookings</span>
                  <span className="p-2 rounded bg-secondary-subtle text-secondary">
                    <BiCalendarEvent size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1">{summary.totalBookings || 0}</h3>
                <span className="text-muted small">All booking records created</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Confirmed Bookings */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Confirmed / Paid</span>
                  <span className="p-2 rounded bg-success-subtle text-success">
                    <BiCheckCircle size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-success">{summary.confirmedBookings || 0}</h3>
                <span className="text-muted small">{summary.paidBookings || 0} paid • {summary.freeBookings || 0} free</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Cancelled Bookings */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Cancellations</span>
                  <span className="p-2 rounded bg-danger-subtle text-danger">
                    <BiXCircle size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-danger">
                  {summary.cancelledBookings || 0}
                  <span className="small fs-6 text-muted ms-2">({summary.cancellationRate || 0}%)</span>
                </h3>
                <span className="text-muted small">Cancellation rate across bookings</span>
              </Card.Body>
            </Card>
          </Col>

          {/* Average Booking Spend */}
          <Col xl={3} md={6}>
            <Card className={`h-100 ${cardBg}`} style={{ borderRadius: '14px' }}>
              <Card.Body className="p-3">
                <div className="d-flex align-items-center justify-content-between mb-2">
                  <span className="text-muted small fw-semibold text-uppercase">Avg Booking Value</span>
                  <span className="p-2 rounded bg-warning-subtle text-warning">
                    <BiTrendingUp size={18} />
                  </span>
                </div>
                <h3 className="fw-bold mb-1 text-warning">₹{(summary.avgBookingValue || 0).toLocaleString('en-IN')}</h3>
                <span className="text-muted small">Average spend per confirmed booking</span>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      ) : null}

      {/* ─── Unified Event Bookings & Cancellation Table ─────────────────── */}
      <EventBookingTable eventId={selectedEventId} event={selectedEvent} />
    </Container>
  );
}

export default EventBookingPage;
