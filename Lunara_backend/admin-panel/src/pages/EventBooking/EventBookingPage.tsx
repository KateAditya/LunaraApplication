import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getPartyEvents, getEventSummary } from '../../api/eventBookings';
import { Container, Row, Col, Card, Form, Spinner } from 'react-bootstrap';
import { format } from 'date-fns';
import { EventBookingTable } from './EventBookingTable';
import { BiCalendarEvent, BiGroup, BiDollarCircle, BiActivity, BiMap } from 'react-icons/bi';
import { useThemeMode } from '../../context/ThemeContext';

export function EventBookingPage() {
  const { mode } = useThemeMode();
  const [selectedEventId, setSelectedEventId] = useState<string>('');

  const { data: eventsData, isLoading: loadingEvents } = useQuery({
    queryKey: ['partyEvents'],
    queryFn: getPartyEvents,
  });

  const { data: summaryData, isLoading: loadingSummary } = useQuery({
    queryKey: ['eventSummary', selectedEventId],
    queryFn: () => getEventSummary(selectedEventId),
    enabled: !!selectedEventId,
  });

  const events = eventsData?.events || [];
  const selectedEvent = events.find((e: any) => e.id === selectedEventId);
  const summary = summaryData?.summary;

  const cardBg = mode === 'dark' ? 'bg-dark text-white border-secondary' : 'bg-white text-dark';
  const cardValueStyle = { fontSize: '1.5rem', fontWeight: 'bold' };

  return (
    <Container fluid className="py-4">
      <div className="d-flex justify-content-between align-items-center mb-4">
        <div>
          <h2 className={`mb-1 ${mode === 'dark' ? 'text-white' : 'text-dark'}`}>Event Booking Management</h2>
          <p className="text-muted mb-0">Manage and monitor all Party Event bookings</p>
        </div>
      </div>

      <Card className={`mb-4 ${cardBg}`}>
        <Card.Body>
          <Form.Group>
            <Form.Label>Select Party Event</Form.Label>
            {loadingEvents ? (
              <div className="py-2"><Spinner animation="border" size="sm" /> Loading events...</div>
            ) : (
              <Form.Select 
                value={selectedEventId} 
                onChange={(e) => setSelectedEventId(e.target.value)}
                className={mode === 'dark' ? 'bg-dark text-white border-secondary' : ''}
              >
                <option value="">-- Select Event --</option>
                {events.map((evt: any) => (
                  <option key={evt.id} value={evt.id}>
                    {evt.title} ({format(new Date(evt.eventDate), 'dd-MM-yyyy')})
                  </option>
                ))}
              </Form.Select>
            )}
          </Form.Group>
        </Card.Body>
      </Card>

      {selectedEvent && (
        <>
          <Card className={`mb-4 ${cardBg}`}>
            <Card.Body>
              <h4 className="mb-3">{selectedEvent.title}</h4>
              <Row>
                <Col md={3}>
                  <p className="mb-1 text-muted"><BiCalendarEvent size={16} className="me-1"/> Event Date</p>
                  <strong>{format(new Date(selectedEvent.eventDate), 'dd-MM-yyyy')}</strong>
                </Col>
                <Col md={3}>
                  <p className="mb-1 text-muted"><BiMap size={16} className="me-1"/> Venue / Location</p>
                  <strong>{selectedEvent.venue?.name || 'Unknown'} | {selectedEvent.area}, {selectedEvent.city}</strong>
                </Col>
                <Col md={3}>
                  <p className="mb-1 text-muted"><BiDollarCircle size={16} className="me-1"/> Entry Price</p>
                  <strong>₹{selectedEvent.entryPrice || 0}</strong>
                </Col>
                <Col md={3}>
                  <p className="mb-1 text-muted"><BiGroup size={16} className="me-1"/> Seat Limit</p>
                  <strong>{selectedEvent.isUnlimited ? 'No Limit' : selectedEvent.seatLimit}</strong>
                </Col>
              </Row>
            </Card.Body>
          </Card>

          {loadingSummary ? (
            <div className="text-center py-4"><Spinner animation="border" /></div>
          ) : summary ? (
            <Row className="mb-4">
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Total Seats</div>
                    <div style={cardValueStyle}>{summary.seatLimit}</div>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Filled Seats</div>
                    <div style={cardValueStyle} className="text-primary">{summary.filledSeats}</div>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Remaining Seats</div>
                    <div style={cardValueStyle} className="text-info">{summary.remainingSeats}</div>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Total Revenue</div>
                    <div style={cardValueStyle} className="text-success">₹{summary.totalRevenue.toLocaleString()}</div>
                  </Card.Body>
                </Card>
              </Col>
              
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Total Bookings</div>
                    <div style={cardValueStyle}>{summary.totalBookings}</div>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Confirmed Bookings</div>
                    <div style={cardValueStyle}>{summary.confirmedBookings}</div>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Paid Bookings</div>
                    <div style={cardValueStyle}>{summary.paidBookings}</div>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={3} className="mb-3">
                <Card className={`h-100 ${cardBg}`}>
                  <Card.Body>
                    <div className="text-muted mb-2">Free Registrations</div>
                    <div style={cardValueStyle}>{summary.freeBookings}</div>
                  </Card.Body>
                </Card>
              </Col>
            </Row>
          ) : null}

          <EventBookingTable eventId={selectedEventId} event={selectedEvent} />
        </>
      )}

      {!selectedEventId && (
        <Card className={`text-center py-5 ${cardBg}`}>
          <Card.Body>
            <BiActivity size={48} className="text-muted mb-3 opacity-50" />
            <h5 className="text-muted">Select an event to view bookings</h5>
          </Card.Body>
        </Card>
      )}
    </Container>
  );
}
