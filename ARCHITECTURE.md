# Lunara Application - Master System Architecture & Technical Specifications

> **System Overview**: Lunara is an enterprise-grade social nightlife, event booking, party planning, and strangers-meet matchmaking platform. It features a Flutter cross-platform mobile/web frontend and a Node.js / Express / TypeScript backend powered by PostgreSQL, Socket.io, Firebase Cloud Messaging (FCM), Razorpay Payments, and Azure Cloud Infrastructure.

---

## 1. Executive Architecture Summary

Lunara is built as a micro-service-ready modular monolith operating on a **Node.js Express TypeScript** backend and a **Flutter Cross-Platform (iOS/Android/Web)** frontend. Real-time events, messaging, and notifications run over a dual-channel architecture: high-frequency real-time updates use **Socket.io WebSockets**, while background out-of-app alerts use **Firebase Cloud Messaging (FCM)**.

```mermaid
graph TB
    subgraph Client_Layer ["1. Frontend Client Layer (Flutter Cross-Platform)"]
        UI_Mobile["📱 Mobile App (iOS / Android)"]
        UI_Web["💻 Web App (Flutter Web)"]
        Service_Layer["⚙️ Core Services (ApiService, PushNotificationService, NotificationNavigator)"]
        UI_Mobile --> Service_Layer
        UI_Web --> Service_Layer
    end

    subgraph API_Gateway ["2. Transport & Gateway Layer"]
        HTTP_REST["🌐 HTTPS REST API (Express Controllers)"]
        WSS_Socket["⚡ Socket.io WebSocket Gateway"]
    end

    Service_Layer ==> HTTP_REST
    Service_Layer ==> WSS_Socket

    subgraph Backend_Engine ["3. Express TypeScript Backend Application Server"]
        App_Server["🚀 Express App Server (server.ts)"]
        
        subgraph Controllers ["Controllers Layer"]
            Ctrl_Auth["Auth & Profile Controller"]
            Ctrl_Party["Party Plan Controller"]
            Ctrl_Group["Group Party Controller"]
            Ctrl_Strangers["Strangers Meet Controller"]
            Ctrl_Booking["Booking Controller"]
            Ctrl_Notif["Notification Controller"]
            Ctrl_Admin["Admin Subsystem Controller"]
        end

        subgraph Domain_Services ["Domain Services Layer"]
            Svc_Ticket["Ticket Service (PDFKit & QR Engine)"]
            Svc_FCM["FCM Push Notification Service"]
            Svc_Socket["Socket.io Event Bus Manager"]
            Svc_Pay["Razorpay Order & Payment Manager"]
        end

        App_Server --> Controllers
        Controllers --> Domain_Services
    end

    HTTP_REST ==> App_Server
    WSS_Socket ==> Svc_Socket

    subgraph Persistence_Layer ["4. Persistence & Storage Layer"]
        Postgres_DB[("🐘 PostgreSQL DB (Sequelize ORM - 43 Models)")]
        File_Storage["📁 Local & Cloud File Storage (/uploads/tickets/)"]
    end

    Backend_Engine ==> Postgres_DB
    Domain_Services ==> File_Storage

    subgraph Cloud_Integrations ["5. Cloud & Third-Party Integrations"]
        Razorpay["💳 Razorpay Payment Gateway"]
        FCM_Cloud["🔔 Firebase Cloud Messaging"]
        Azure_Blob["☁️ Azure Blob Storage"]
        Azure_Face["👤 Azure AI Face Verification API"]
        Google_Maps["🗺️ Google Maps Platform API"]
    end

    Svc_Pay <--> Razorpay
    Svc_FCM <--> FCM_Cloud
    Svc_Ticket <--> Azure_Blob
    Ctrl_Auth <--> Azure_Face
    Service_Layer <--> Google_Maps
```

---

## 2. Complete Database Entity-Relationship Diagram (ERD)

The database consists of **43 Sequelize Models** managed in PostgreSQL with strict data isolation, foreign key constraints, and index optimization.

```mermaid
erDiagram
    User ||--o{ UserProfile : "has"
    User ||--o{ UserPhoto : "has photos"
    User ||--o{ UserPreference : "has preferences"
    User ||--o{ PartyPlan : "hosts"
    User ||--o{ PartyPlanRequest : "requests join"
    User ||--o{ GroupParty : "creates"
    User ||--o{ StrangersMeetRequest : "hosts"
    User ||--o{ StrangersMeetJoiner : "joins"
    User ||--o{ Booking : "makes"
    User ||--o{ Payment : "transacts"
    User ||--o{ UserMatch : "matches with"
    User ||--o{ Conversation : "participates in"
    User ||--o{ UserSubscription : "subscribes"
    User ||--o{ SafetyCheck : "submits"

    Venue ||--o{ VenueImage : "has images"
    Venue ||--o{ PartyPlan : "hosts"
    Venue ||--o{ GroupParty : "hosts"
    Venue ||--o{ StrangersMeetRequest : "hosts"
    Venue ||--o{ Booking : "reserved at"

    PartyPlan ||--o{ PartyPlanRequest : "receives requests"
    StrangersMeetRequest ||--o{ StrangersMeetJoiner : "receives joiners"
    Conversation ||--o{ Message : "contains"

    User {
        uuid id PK
        string firstName
        string lastName
        string username UK
        string email UK
        string mobileNumber UK
        string profileImageUrl
        string fcmToken
        string subscriptionTier
        boolean isVerified
        timestamp clearedNotificationsAt
    }

    Venue {
        uuid id PK
        string name
        string addressLine1
        string area
        string city
        decimal groupPartyChargePerPerson
        decimal tableBookingCharges
        float latitude
        float longitude
    }

    Booking {
        uuid id PK
        uuid userId FK
        uuid venueId FK
        string goingMode "party_request | solo"
        string status "pending | confirmed | cancelled | completed"
        string paymentStatus "unpaid | paid | refunded"
        string ticketCode "PP-XXXXXX | GP-XXXXXX | SM-XXXXXX"
        string ticketUrl
        json specialRequests "Metadata (planId, requestId, hostId, joinerId)"
    }

    PartyPlan {
        uuid id PK
        uuid userId FK
        uuid venueId FK
        timestamp planDateTime
        string depositAmount
        string status "active | matched | completed"
    }

    PartyPlanRequest {
        uuid id PK
        uuid planId FK
        uuid requesterId FK
        string status "pending | accepted | rejected"
        string joinerPaymentStatus "unpaid | paid"
        string ticketCode
        string ticketUrl
    }

    GroupParty {
        uuid id PK
        uuid userId FK
        uuid venueId FK
        integer numberOfFriends
        decimal totalAmount
        string status "pending | approved | confirmed"
        string paymentStatus "pending | paid"
        string ticketCode
        string ticketUrl
    }

    StrangersMeetRequest {
        uuid id PK
        uuid userId FK
        uuid venueId FK
        string subject
        string tagline
        timestamp eventDateTime
        integer numberOfPersons
        decimal chargesPerHead
        string status "pending | approved | completed"
        string paymentStatus "unpaid | paid"
        string ticketId
        string ticketUrl
    }

    Payment {
        uuid id PK
        uuid userId FK
        string razorpayOrderId UK
        string razorpayPaymentId UK
        decimal amount
        string status "created | captured | failed"
    }

    UserMatch {
        uuid id PK
        uuid userId FK
        uuid matchedUserId FK
        boolean isSuperLike
        string status "pending | matched | rejected"
    }
```

---

## 3. End-to-End Subsystem Flowcharts

### 3.1 Party Plan Subsystem Flow (Host + Partner)

```mermaid
graph TD
    A["Host posts Party Plan for Venue"] --> B["Plan listed in Live Feed"]
    B --> C["Partner sends Join Request"]
    C --> D["Host receives Notification & Accepts"]
    D --> E["Partner pays Deposit via Razorpay"]
    E --> F["Backend creates Booking Record (PP-XXXXXX)"]
    F --> G["PDFKit Service generates Light Theme PDF Ticket"]
    G --> H["Save ticketCode & ticketUrl to DB"]
    H --> I["PartyPlanTicketScreen renders Light Theme Card"]
    I --> J["User taps SHARE TICKET -> Shares direct HTTP/HTTPS PDF URL"]
```

---

### 3.2 Group Party Subsystem Flow (Small <20 & Large >=20 Guests)

```mermaid
graph TD
    A1["Host creates Group Party"] --> B1["Select Venue & Number of Friends"]
    B1 --> C1{"Check Guest Count"}
    C1 -- "< 20 Friends" --> D1["Instant Auto-Approval"]
    C1 -- ">= 20 Friends" --> E1["Sent to Admin Approval Queue"]
    E1 --> F1["Admin Approves Request & Sets Final Price"]
    D1 --> G1["Host pays Razorpay Order"]
    F1 --> G1
    G1 --> H1["Backend creates Booking (GP-XXXXXX) & PDF Ticket"]
    H1 --> I1["LargePartyTicketScreen displays Host Profile + Group Size (e.g. 15 Members)"]
```

---

### 3.3 Strangers Meet Subsystem Flow (21–50 Persons)

```mermaid
graph TD
    A2["Host creates Strangers Meet Request"] --> B2["Set Subject, Tagline, Date & Charges/Head"]
    B2 --> C2["Admin Verification & Approval"]
    C2 --> D2["Host pays Security Deposit"]
    D2 --> E2["Meet published for Participants to Join"]
    E2 --> F2["Joiners submit Request & Pay Per-Head Amount"]
    F2 --> G2["Event Host receives Settlement Payout"]
    G2 --> H2["StrangersMeetTicketScreen displays Event Host Profile + Meet Size"]
```

---

### 3.4 Real-Time Notification & Top Floating Banner Subsystem Flow

```mermaid
graph TD
    A3["Event Triggered (Match / Request / Payment)"] --> B3["Save Notification in DB"]
    B3 --> C3["Socket.io emits 'notification_created' event"]
    C3 --> D3{"App In Foreground?"}
    D3 -- Yes --> E3["TopNotificationBanner overlay slides down from top (4s display)"]
    D3 -- No --> F3["FCM sends High-Priority Android/iOS System Notification"]
    E3 --> G3["Tap Banner -> PushNotificationService.navigateFromPayload(data)"]
    F3 --> G3
    G3 --> H3["Open NotificationCenterScreen (Grouped by TODAY, YESTERDAY, THIS WEEK, EARLIER)"]
```

---

## 4. Sequence Diagrams

### 4.1 On-The-Fly PDF Ticket Persistence Sequence

```mermaid
sequenceDiagram
    autonumber
    actor User as Mobile Client UI
    participant API as Express API Server
    participant PDFEngine as PDFKit Service (ticketService)
    participant DB as PostgreSQL Database
    participant Share as Native Share Handler

    User->>API: GET /api/mobile/party-plans/requests/:id/ticket
    API->>DB: Query Request & Booking Record
    alt Ticket PDF not generated yet
        API->>PDFEngine: generateTicketForBookingHelper(bookingId)
        PDFEngine->>PDFEngine: Build Pure White Light Theme PDF
        PDFEngine->>DB: Save ticketUrl & ticketCode
    end
    API-->>User: Return Ticket Details (Host, Partner, Venue, ticketUrl)
    User->>User: Render Light Theme Pass (Host Left, Partner Right, Secure Pay Card)
    User->>Share: Taps "SHARE TICKET" -> Shares Direct Link URL (ticketUrl)
```

---

### 4.2 Real-Time Chat & Notification Sequence

```mermaid
sequenceDiagram
    autonumber
    actor UserA as Sender (User A)
    participant Socket as Socket.io Server
    participant API as Express Backend
    participant FCM as Firebase FCM
    actor UserB as Receiver (User B)

    UserA->>API: POST /api/mobile/chat/message
    API->>DB: Save Message to DB
    API->>Socket: io.to('user_' + receiverId).emit('new_message', msg)
    par Foreground Overlay
        Socket-->>UserB: Socket Event ('new_message')
        UserB->>UserB: TopNotificationBanner.show(SenderName, MessageBody)
    and Background Push
        API->>FCM: sendPushNotification(fcmToken, {title, body})
        FCM-->>UserB: High Priority Heads-up Banner Notification
    end
```

---

## 5. Security & Azure AI Biometric Authentication

```mermaid
flowchart TD
    A["User submits Verification Request"] --> B["Capture Live Selfie (XFile)"]
    B --> C["Fetch Primary Profile Photo"]
    C --> D["POST /api/mobile/auth/verify-face"]
    D --> E["Azure AI Face Service (Face API)"]
    E --> F["Calculate Face Distance & Match Confidence Score"]
    F --> G{"Confidence > 0.6?"}
    G -- Yes --> H["Set isVerified = true in User Table"]
    H --> I["Display Blue Verified Shield Badge on Profile"]
    G -- No --> J["Return Failure: Face Match Confidence Low"]
```

---

## 6. Frontend Component Architecture (Flutter)

```mermaid
graph TD
    Root["App Root (main.dart)"] --> NavKey["NotificationNavigator.navigatorKey"]
    Root --> ThemeEngine["LunaraTheme (Light Mode & Midnight Dark Engine)"]

    NavKey --> NavigationHub["Navigation Hub (live_feed_screen.dart)"]

    subgraph Ticket_System ["Ticket Screens Engine"]
        NavigationHub --> Screen_PPTicket["PartyPlanTicketScreen (Host + Partner)"]
        NavigationHub --> Screen_GPTicket["LargePartyTicketScreen (Host + Group Size)"]
        NavigationHub --> Screen_SMTicket["StrangersMeetTicketScreen (Host + Meet Size)"]
    end

    subgraph Notification_System ["Notification Center & Overlays"]
        NavigationHub --> Screen_Notif["NotificationCenterScreen (Date Grouped)"]
        Root --> Overlay_Banner["TopNotificationBanner (WhatsApp Floating Overlay)"]
    end

    subgraph Core_Widgets ["Reusable Core UI Components"]
        Widget_Ticket["LunaraTicketWidget (Light Mode Pass, Dashed Cutouts)"]
        Widget_Profile["LunaraProfileImage (Gradient Border, Status Ring)"]
        Widget_Glass["GlassCard (Backdrop Blur, Soft Borders)"]
    end

    Screen_PPTicket --> Widget_Ticket
    Screen_GPTicket --> Widget_Ticket
    Screen_SMTicket --> Widget_Ticket

    Screen_PPTicket --> Widget_Profile
    Screen_GPTicket --> Widget_Profile
    Screen_SMTicket --> Widget_Profile

    Screen_Notif --> Widget_Glass
```

---

## 7. Backend Directory & Layered Architecture

```mermaid
graph TD
    subgraph Boot ["1. Server Entry Point"]
        Server["server.ts (Express Initialization, Static Assets /uploads, Routing)"]
    end

    subgraph Middleware_Layer ["2. Middleware Layer"]
        MW_Auth["auth.ts (JWT Bearer Verification & User Scoping)"]
        MW_Val["validate.ts (Request Validation Schemas)"]
    end

    subgraph Route_Layer ["3. API Route Modules"]
        R_Party["mobilePartyPlan.ts"]
        R_Group["mobileGroupParty.ts"]
        R_Strangers["mobileStrangersMeet.ts"]
        R_User["mobileUser.ts"]
        R_Booking["mobileBooking.ts"]
        R_Sub["mobileSubscription.ts"]
    end

    subgraph Controller_Layer ["4. Business Logic Controllers"]
        C_Party["partyPlanController.ts"]
        C_Group["mobileGroupPartyController.ts"]
        C_Strangers["strangersMeetController.ts"]
        C_Booking["mobileBookingController.ts"]
    end

    subgraph Service_Layer ["5. Domain Service Layer"]
        S_Ticket["ticketService.ts (PDF Ticket Generation & Storage)"]
        S_FCM["fcmService.ts (Multicast & Push Dispatcher)"]
    end

    subgraph Model_Layer ["6. Database Layer (Sequelize ORM)"]
        M_User["User.ts"]
        M_Venue["Venue.ts"]
        M_Booking["Booking.ts"]
        M_PP["PartyPlan.ts & PartyPlanRequest.ts"]
        M_GP["GroupParty.ts"]
        M_SM["StrangersMeetRequest.ts & StrangersMeetJoiner.ts"]
    end

    Server --> MW_Auth
    MW_Auth --> MW_Val
    MW_Val --> Route_Layer
    Route_Layer --> Controller_Layer
    Controller_Layer --> Service_Layer
    Controller_Layer --> Model_Layer
    Service_Layer --> Model_Layer
```

---

## 8. Complete REST API Routing Matrix

| Route Path | Method | Controller Handler | Purpose |
| :--- | :--- | :--- | :--- |
| `/api/mobile/auth/login` | `POST` | `mobileAuth.ts` | Mobile Phone OTP & JWT Auth Login |
| `/api/mobile/auth/verify-face` | `POST` | `mobileAuth.ts` | Azure AI Face Biometric Verification |
| `/api/mobile/user/userprofile` | `GET` | `mobileUser.ts` | Fetch Current User Profile Details |
| `/api/mobile/user/notifications` | `GET` | `mobileUser.ts` | Real-time Compiled Notifications (Date Grouped) |
| `/api/mobile/user/notifications/:id/read` | `PATCH` | `mobileUser.ts` | Mark Notification as Read |
| `/api/mobile/user/notifications/clear-all` | `POST` | `mobileUser.ts` | Clear All Notifications for User |
| `/api/mobile/party-plans` | `POST` | `partyPlanController.ts` | Host Creates Party Plan for Venue |
| `/api/mobile/party-plans/requests/:id/ticket` | `GET` | `partyPlanController.ts` | Fetch Party Plan Ticket Data & Generate PDF |
| `/api/mobile/group-parties` | `POST` | `mobileGroupPartyController.ts` | Create Group Party (<20 or >=20 Friends) |
| `/api/mobile/group-parties/:id/ticket` | `GET` | `mobileGroupPartyController.ts` | Fetch Group Party Ticket (Single Host + Size) |
| `/api/mobile/strangers-meet/requests` | `POST` | `strangersMeetController.ts` | Host Submits Strangers Meet Event |
| `/api/mobile/strangers-meet/requests/:id/ticket` | `GET` | `strangersMeetController.ts` | Fetch Strangers Meet Ticket (Host + Meet Size) |
| `/api/mobile/bookings` | `GET` | `mobileBookingController.ts` | Fetch All Confirmed & Pending Bookings |

---

## 9. Production Deployment Infrastructure Blueprint

```mermaid
graph TB
    subgraph Public_Clients ["Client Access Layer"]
        iOS_App["🍎 iOS App Store Release"]
        Android_App["📱 Google Play Store Release"]
        Web_App["🌐 Web Browser Application"]
    end

    subgraph Gateway ["Reverse Proxy & SSL Layer"]
        Nginx_Proxy["🛡️ Nginx Reverse Proxy (SSL Certificate, Gzip, Rate Limiter)"]
    end

    subgraph Application_Cluster ["App Server Infrastructure"]
        Node_Cluster["💻 Azure App Service (Node.js Linux PM2 Cluster)"]
    end

    subgraph Data_Services ["Cloud Data Services"]
        Postgres_Cloud[("🐘 Azure Database for PostgreSQL Flexible Server")]
        Azure_Storage["☁️ Azure Blob Storage (Profile Media & PDF Tickets)"]
    end

    subgraph Third_Party_Gateways ["External Gateways"]
        Razorpay_API["💳 Razorpay Payment API"]
        Firebase_FCM["🔔 Firebase FCM Push Gateway"]
        Azure_AI["👤 Azure AI Vision & Face API"]
    end

    iOS_App ==> Nginx_Proxy
    Android_App ==> Nginx_Proxy
    Web_App ==> Nginx_Proxy

    Nginx_Proxy ==> Node_Cluster
    Node_Cluster ==> Postgres_Cloud
    Node_Cluster ==> Azure_Storage

    Node_Cluster <--> Razorpay_API
    Node_Cluster <--> Firebase_FCM
    Node_Cluster <--> Azure_AI
```

---

## 10. Key Specifications Summary

| System Aspect | Implementation Specification |
| :--- | :--- |
| **Frontend Framework** | Flutter Cross-Platform (iOS, Android, Web) with Light Theme Ticket System (`#F6F7FB`) & Dark Theme Shell (`#0B0914`). |
| **Backend Framework** | Node.js, Express, TypeScript, REST API, WebSockets (Socket.io). |
| **Database Engine** | PostgreSQL with Sequelize ORM (43 Entities, FK Constraints, Indexing). |
| **Real-Time System** | Dual-channel: Socket.io for active app foreground session, FCM for background OS push notifications. |
| **Ticket System** | On-the-fly PDF generation (`PDFKit`), DB persistence (`ticketCode`, `ticketUrl`), direct URL link sharing. |
| **Biometric Security** | Azure AI Face Service verification matching selfie vs profile image with >0.6 confidence. |
