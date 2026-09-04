import { Modal, Button, Row, Col, Badge } from 'react-bootstrap';
import { format } from 'date-fns';
import { useThemeMode } from '../../context/ThemeContext';

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

interface EventBookingDetailModalProps {
  show: boolean;
  onHide: () => void;
  booking: any;
  event: any;
}

export function EventBookingDetailModal({ show, onHide, booking, event }: EventBookingDetailModalProps) {
  const { mode } = useThemeMode();

  const isDark = mode === 'dark';
  const modalClass = isDark ? 'bg-dark text-white' : '';
  const headerClass = isDark ? 'border-secondary' : '';
  const textClass = isDark ? 'text-light' : 'text-dark';

  const userPhone = booking?.user?.phone || booking?.user?.mobile || booking?.mobileNumber || 'N/A';
  const isCancelled = booking?.status === 'cancelled';

  return (
    <Modal show={show} onHide={onHide} size="lg" centered contentClassName={modalClass}>
      <Modal.Header closeButton closeVariant={isDark ? 'white' : undefined} className={headerClass}>
        <Modal.Title className="fw-bold fs-5">
          Party Event Booking #{booking?.bookingNumber}
        </Modal.Title>
      </Modal.Header>
      <Modal.Body>
        {booking && (
          <Row className="g-4">
            <Col md={6}>
              <h6 className={`fw-bold text-uppercase small ${textClass}`}>Event Information</h6>
              <div className="p-3 rounded bg-light bg-opacity-25 border">
                <div className="mb-1"><strong>Event:</strong> {event?.title || 'Party Event'}</div>
                <div className="mb-1"><strong>Date:</strong> {safeFormat(event?.eventDate, 'dd-MM-yyyy', 'N/A')}</div>
                <div className="mb-1"><strong>Venue:</strong> {event?.venue?.name || 'Venue TBA'}</div>
                <div className="mb-1"><strong>Location:</strong> {event?.area || ''}, {event?.city || ''}</div>
                <div><strong>Standard Entry Price:</strong> ₹{event?.entryPrice || 0}</div>
              </div>
            </Col>

            <Col md={6}>
              <h6 className={`fw-bold text-uppercase small ${textClass}`}>Customer Details</h6>
              <div className="p-3 rounded bg-light bg-opacity-25 border">
                <div className="mb-1">
                  <strong>Name:</strong> {booking.user ? `${booking.user.firstName || ''} ${booking.user.lastName || ''}`.trim() : 'Guest Customer'}
                </div>
                <div className="mb-1"><strong>Phone:</strong> {userPhone}</div>
                <div className="mb-1"><strong>Email:</strong> {booking.user?.email || 'N/A'}</div>
                <div><strong>Customer ID:</strong> <span className="font-monospace small">{booking.userId}</span></div>
              </div>
            </Col>

            <Col md={6}>
              <h6 className={`fw-bold text-uppercase small ${textClass}`}>Booking & Attendance</h6>
              <div className="p-3 rounded bg-light bg-opacity-25 border">
                <div className="mb-1"><strong>Booked At:</strong> {safeFormat(booking.createdAt, 'dd-MM-yyyy HH:mm')}</div>
                <div className="mb-1"><strong>Guests / Quantity:</strong> {booking.numberOfGuests || 1} Entries</div>
                <div className="mb-1"><strong>Total Booking Amount:</strong> ₹{booking.totalAmount || 0}</div>
                <div>
                  <strong>Booking Status:</strong>{' '}
                  <Badge bg={booking.status === 'confirmed' ? 'success' : booking.status === 'cancelled' ? 'danger' : 'warning'}>
                    {(booking.status || 'PENDING').toUpperCase()}
                  </Badge>
                </div>
              </div>
            </Col>

            <Col md={6}>
              <h6 className={`fw-bold text-uppercase small ${textClass}`}>Payment & Transactions</h6>
              <div className="p-3 rounded bg-light bg-opacity-25 border">
                <div className="mb-1">
                  <strong>Payment Status:</strong>{' '}
                  {Number(booking.totalAmount) === 0 ? (
                    <Badge bg="success">FREE</Badge>
                  ) : (
                    <Badge bg={booking.paymentStatus === 'paid' ? 'success' : booking.paymentStatus === 'refunded' ? 'info' : booking.paymentStatus === 'failed' ? 'danger' : 'warning'}>
                      {(booking.paymentStatus || 'UNPAID').toUpperCase()}
                    </Badge>
                  )}
                </div>
                {booking.razorpayOrderId && (
                  <div className="mb-1 font-monospace small"><strong>Razorpay Order ID:</strong> {booking.razorpayOrderId}</div>
                )}
                {booking.ticketCode && (
                  <div className="font-monospace small"><strong>Ticket Code:</strong> {booking.ticketCode}</div>
                )}
              </div>
            </Col>

            {/* Cancellation & Refund Notice if Cancelled */}
            {isCancelled && (
              <Col md={12}>
                <div className="alert alert-danger mb-0">
                  <h6 className="fw-bold mb-1">Cancellation & Refund Record</h6>
                  <div className="small mb-1">
                    <strong>Reason:</strong> {booking.cancellationReason || 'No reason provided'}
                  </div>
                  {booking.cancelledAt && (
                    <div className="small mb-1">
                      <strong>Cancelled At:</strong> {safeFormat(booking.cancelledAt, 'dd-MM-yyyy HH:mm')}
                    </div>
                  )}
                  {booking.refundMethod && (
                    <div className="small">
                      <strong>Refund Route:</strong> {booking.refundMethod} {booking.upiId ? `(UPI: ${booking.upiId})` : ''}
                    </div>
                  )}
                </div>
              </Col>
            )}

            {booking.ticket && (
              <Col md={12}>
                <h6 className={`fw-bold text-uppercase small ${textClass}`}>Digital Pass / QR Ticket</h6>
                <div className="p-3 rounded bg-light bg-opacity-25 border d-flex justify-content-between align-items-center">
                  <div>
                    <div className="fw-bold font-monospace">{booking.ticket.ticketNumber}</div>
                    <div className="text-muted small">Generated on {safeFormat(booking.ticket.createdAt, 'dd-MM-yyyy HH:mm')}</div>
                  </div>
                  <Badge bg={booking.ticket.status === 'valid' ? 'success' : 'secondary'} className="fs-6">
                    {(booking.ticket.status || 'ACTIVE').toUpperCase()}
                  </Badge>
                </div>
              </Col>
            )}
          </Row>
        )}
      </Modal.Body>
      <Modal.Footer className={headerClass}>
        <Button variant="secondary" onClick={onHide}>
          Close
        </Button>
      </Modal.Footer>
    </Modal>
  );
}

export default EventBookingDetailModal;
