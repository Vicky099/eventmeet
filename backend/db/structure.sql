SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_memberships (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    account_id uuid NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: account_switches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_switches (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    account_id uuid NOT NULL,
    token character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    redeemed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid NOT NULL,
    name character varying NOT NULL,
    subdomain_slug character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    plan character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    contact_email character varying,
    contact_num character varying,
    sender_email character varying,
    time_zone character varying DEFAULT 'UTC'::character varying NOT NULL,
    agency_id uuid
);


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: agencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agencies (
    id uuid NOT NULL,
    name character varying NOT NULL,
    contact_email character varying,
    contact_num character varying,
    status integer DEFAULT 0 NOT NULL,
    price_per_event numeric(12,2),
    currency character varying DEFAULT 'INR'::character varying NOT NULL,
    events_granted integer DEFAULT 0 NOT NULL,
    events_used integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    subdomain_slug character varying,
    billing_cycle integer DEFAULT 0 NOT NULL,
    annual_price numeric(12,2)
);


--
-- Name: agency_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agency_memberships (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    agency_id uuid NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: attendances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendances (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participant_id uuid NOT NULL,
    scan_event_id uuid,
    "from" integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    time_spent_seconds integer,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    session_id uuid
);


--
-- Name: badge_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.badge_templates (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    name character varying NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    output_type integer DEFAULT 0 NOT NULL,
    width_cm numeric(6,2) NOT NULL,
    height_cm numeric(6,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: badges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.badges (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    ticket_category_id uuid,
    badge_template_id uuid,
    name character varying NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    output_type integer DEFAULT 0 NOT NULL,
    width_cm numeric(6,2) NOT NULL,
    height_cm numeric(6,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bulk_print_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bulk_print_runs (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    print_station_id uuid NOT NULL,
    created_by_id uuid NOT NULL,
    "limit" integer NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: custom_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_fields (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    label character varying NOT NULL,
    field_type integer DEFAULT 0 NOT NULL,
    options text,
    required boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    registration_form_id uuid NOT NULL
);


--
-- Name: email_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_templates (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    kind integer NOT NULL,
    subject character varying NOT NULL,
    html_body text DEFAULT ''::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: event_live_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_live_stats (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    registered_count integer DEFAULT 0 NOT NULL,
    checked_in_count integer DEFAULT 0 NOT NULL,
    checked_out_count integer DEFAULT 0 NOT NULL,
    occupancy_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: event_staff_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_staff_assignments (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    mode integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    banner_orientation integer DEFAULT 0 NOT NULL,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone NOT NULL,
    address text,
    meeting_link character varying,
    participant_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    map_url character varying,
    published_at timestamp(6) without time zone,
    seat_limit integer,
    participant_approval_required boolean DEFAULT false NOT NULL,
    has_seat_limit boolean DEFAULT false NOT NULL,
    description text,
    is_paid boolean DEFAULT false NOT NULL,
    send_registration_email boolean DEFAULT false NOT NULL,
    scheduled_report_frequency integer DEFAULT 0 NOT NULL,
    last_report_sent_at timestamp(6) without time zone,
    auto_print_enabled boolean DEFAULT false NOT NULL,
    default_print_station_id uuid
);


--
-- Name: export_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.export_files (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    created_by_id uuid NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    fields jsonb DEFAULT '[]'::jsonb NOT NULL,
    format integer DEFAULT 0 NOT NULL
);


--
-- Name: govt_id_import_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.govt_id_import_files (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    created_by_id uuid NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    total_rows integer,
    processed_rows integer DEFAULT 0 NOT NULL,
    created_count integer DEFAULT 0 NOT NULL,
    duplicate_count integer DEFAULT 0 NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    row_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: govt_ids; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.govt_ids (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    value character varying NOT NULL,
    participant_id uuid,
    assigned_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_files (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    created_by_id uuid NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    total_rows integer,
    processed_rows integer DEFAULT 0 NOT NULL,
    created_count integer DEFAULT 0 NOT NULL,
    duplicate_count integer DEFAULT 0 NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    row_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid NOT NULL,
    account_id uuid,
    event_id uuid,
    amount numeric(12,2) NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    utr_reference character varying,
    submitted_by_id uuid,
    submitted_at timestamp(6) without time zone,
    verified_by_id uuid,
    verified_at timestamp(6) without time zone,
    rejection_reason text,
    currency character varying DEFAULT 'INR'::character varying NOT NULL,
    agency_id uuid
);


--
-- Name: live_metric_buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.live_metric_buckets (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    metric integer NOT NULL,
    bucket_at timestamp(6) without time zone NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    notifiable_type character varying NOT NULL,
    notifiable_id uuid NOT NULL,
    channel integer NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    "to" character varying NOT NULL,
    subject character varying,
    body text,
    error_message text,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_grants (
    id bigint NOT NULL,
    resource_owner_id uuid NOT NULL,
    application_id bigint NOT NULL,
    token character varying NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone
);


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_grants_id_seq OWNED BY public.oauth_access_grants.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_tokens (
    id bigint NOT NULL,
    resource_owner_id uuid,
    application_id bigint NOT NULL,
    token character varying NOT NULL,
    refresh_token character varying,
    expires_in integer,
    scopes character varying,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    previous_refresh_token character varying DEFAULT ''::character varying NOT NULL
);


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_tokens_id_seq OWNED BY public.oauth_access_tokens.id;


--
-- Name: oauth_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_applications (
    id bigint NOT NULL,
    name character varying NOT NULL,
    uid character varying NOT NULL,
    secret character varying NOT NULL,
    redirect_uri text DEFAULT ''::text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    confidential boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account_id uuid NOT NULL
);


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_applications_id_seq OWNED BY public.oauth_applications.id;


--
-- Name: participants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.participants (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    ticket_category_id uuid,
    hex_id character varying NOT NULL,
    client_participant_id character varying NOT NULL,
    govt_id character varying,
    rf_id character varying,
    name character varying NOT NULL,
    email character varying,
    contact_num character varying,
    company character varying,
    department character varying,
    "position" character varying,
    nationality character varying,
    country character varying,
    source integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    custom_field_values jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    title character varying,
    first_name character varying,
    last_name character varying
);


--
-- Name: print_agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.print_agents (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    print_station_id uuid NOT NULL,
    jti character varying NOT NULL,
    paired_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    connected boolean DEFAULT false NOT NULL,
    last_seen_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: print_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.print_jobs (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    print_station_id uuid NOT NULL,
    participant_id uuid NOT NULL,
    bulk_print_run_id uuid,
    sequence integer,
    status integer DEFAULT 0 NOT NULL,
    source integer DEFAULT 0 NOT NULL,
    error_message text,
    sent_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: print_stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.print_stations (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    name character varying NOT NULL,
    printer_name character varying,
    pairing_code character varying,
    pairing_code_expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: registration_forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.registration_forms (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    catalog_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    catalog_field_positions jsonb DEFAULT '{}'::jsonb NOT NULL,
    uniqueness_fields jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: scan_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scan_events (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participant_id uuid NOT NULL,
    scan_type integer DEFAULT 0 NOT NULL,
    source integer DEFAULT 1 NOT NULL,
    scanned_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    session_id uuid
);


--
-- Name: schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedules (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    speaker_id uuid NOT NULL,
    session_id uuid,
    title character varying NOT NULL,
    details text,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: session_live_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_live_stats (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    checked_in_count integer DEFAULT 0 NOT NULL,
    checked_out_count integer DEFAULT 0 NOT NULL,
    occupancy_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    name character varying NOT NULL,
    room character varying,
    track character varying,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone NOT NULL,
    seat_limit integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: speakers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.speakers (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    name character varying NOT NULL,
    company character varying,
    bio text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    country character varying,
    nationality character varying,
    contact_num character varying,
    email character varying,
    company_details text,
    event_id uuid NOT NULL
);


--
-- Name: tenant_domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_domains (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    domain character varying NOT NULL,
    kind integer DEFAULT 0 NOT NULL,
    verified_at timestamp(6) without time zone,
    tls_status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ticket_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ticket_categories (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    name character varying NOT NULL,
    total_count integer,
    sold_count integer DEFAULT 0 NOT NULL,
    remain_count integer DEFAULT 0,
    document_required boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    registration_form_id uuid
);


--
-- Name: ticket_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ticket_reservations (
    id uuid NOT NULL,
    account_id uuid NOT NULL,
    event_id uuid NOT NULL,
    ticket_category_id uuid NOT NULL,
    seat_count integer NOT NULL,
    holder_name character varying NOT NULL,
    holder_email character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    claim_token character varying NOT NULL,
    cancelled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    platform_staff boolean DEFAULT false NOT NULL,
    contact_num character varying,
    must_reset_password boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_access_grants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_grants_id_seq'::regclass);


--
-- Name: oauth_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_tokens_id_seq'::regclass);


--
-- Name: oauth_applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications ALTER COLUMN id SET DEFAULT nextval('public.oauth_applications_id_seq'::regclass);


--
-- Name: account_memberships account_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT account_memberships_pkey PRIMARY KEY (id);


--
-- Name: account_switches account_switches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_switches
    ADD CONSTRAINT account_switches_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: agencies agencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agencies
    ADD CONSTRAINT agencies_pkey PRIMARY KEY (id);


--
-- Name: agency_memberships agency_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agency_memberships
    ADD CONSTRAINT agency_memberships_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attendances attendances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT attendances_pkey PRIMARY KEY (id);


--
-- Name: badge_templates badge_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badge_templates
    ADD CONSTRAINT badge_templates_pkey PRIMARY KEY (id);


--
-- Name: badges badges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT badges_pkey PRIMARY KEY (id);


--
-- Name: bulk_print_runs bulk_print_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_print_runs
    ADD CONSTRAINT bulk_print_runs_pkey PRIMARY KEY (id);


--
-- Name: custom_fields custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT custom_fields_pkey PRIMARY KEY (id);


--
-- Name: email_templates email_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (id);


--
-- Name: event_live_stats event_live_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_live_stats
    ADD CONSTRAINT event_live_stats_pkey PRIMARY KEY (id);


--
-- Name: event_staff_assignments event_staff_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_staff_assignments
    ADD CONSTRAINT event_staff_assignments_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: export_files export_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_files
    ADD CONSTRAINT export_files_pkey PRIMARY KEY (id);


--
-- Name: govt_id_import_files govt_id_import_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_id_import_files
    ADD CONSTRAINT govt_id_import_files_pkey PRIMARY KEY (id);


--
-- Name: govt_ids govt_ids_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_ids
    ADD CONSTRAINT govt_ids_pkey PRIMARY KEY (id);


--
-- Name: import_files import_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_files
    ADD CONSTRAINT import_files_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: live_metric_buckets live_metric_buckets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.live_metric_buckets
    ADD CONSTRAINT live_metric_buckets_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_grants oauth_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT oauth_access_grants_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_tokens oauth_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT oauth_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth_applications oauth_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications
    ADD CONSTRAINT oauth_applications_pkey PRIMARY KEY (id);


--
-- Name: participants participants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT participants_pkey PRIMARY KEY (id);


--
-- Name: print_agents print_agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_agents
    ADD CONSTRAINT print_agents_pkey PRIMARY KEY (id);


--
-- Name: print_jobs print_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_jobs
    ADD CONSTRAINT print_jobs_pkey PRIMARY KEY (id);


--
-- Name: print_stations print_stations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_stations
    ADD CONSTRAINT print_stations_pkey PRIMARY KEY (id);


--
-- Name: registration_forms registration_forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registration_forms
    ADD CONSTRAINT registration_forms_pkey PRIMARY KEY (id);


--
-- Name: scan_events scan_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT scan_events_pkey PRIMARY KEY (id);


--
-- Name: schedules schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT schedules_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: session_live_stats session_live_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_live_stats
    ADD CONSTRAINT session_live_stats_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: speakers speakers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.speakers
    ADD CONSTRAINT speakers_pkey PRIMARY KEY (id);


--
-- Name: tenant_domains tenant_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_domains
    ADD CONSTRAINT tenant_domains_pkey PRIMARY KEY (id);


--
-- Name: ticket_categories ticket_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_categories
    ADD CONSTRAINT ticket_categories_pkey PRIMARY KEY (id);


--
-- Name: ticket_reservations ticket_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_reservations
    ADD CONSTRAINT ticket_reservations_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_ticket_category_id_status_created_at_61ceb40daf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_ticket_category_id_status_created_at_61ceb40daf ON public.ticket_reservations USING btree (ticket_category_id, status, created_at);


--
-- Name: index_account_memberships_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_account_id ON public.account_memberships USING btree (account_id);


--
-- Name: index_account_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_user_id ON public.account_memberships USING btree (user_id);


--
-- Name: index_account_memberships_on_user_id_and_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_memberships_on_user_id_and_account_id ON public.account_memberships USING btree (user_id, account_id);


--
-- Name: index_account_switches_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_switches_on_account_id ON public.account_switches USING btree (account_id);


--
-- Name: index_account_switches_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_switches_on_token ON public.account_switches USING btree (token);


--
-- Name: index_account_switches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_switches_on_user_id ON public.account_switches USING btree (user_id);


--
-- Name: index_accounts_on_agency_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounts_on_agency_id ON public.accounts USING btree (agency_id);


--
-- Name: index_accounts_on_subdomain_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_subdomain_slug ON public.accounts USING btree (subdomain_slug);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_agencies_on_subdomain_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_agencies_on_subdomain_slug ON public.agencies USING btree (subdomain_slug);


--
-- Name: index_agency_memberships_on_agency_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agency_memberships_on_agency_id ON public.agency_memberships USING btree (agency_id);


--
-- Name: index_agency_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agency_memberships_on_user_id ON public.agency_memberships USING btree (user_id);


--
-- Name: index_agency_memberships_on_user_id_and_agency_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_agency_memberships_on_user_id_and_agency_id ON public.agency_memberships USING btree (user_id, agency_id);


--
-- Name: index_attendances_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_account_id ON public.attendances USING btree (account_id);


--
-- Name: index_attendances_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_event_id ON public.attendances USING btree (event_id);


--
-- Name: index_attendances_on_event_participant_from_status_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_event_participant_from_status_occurred_at ON public.attendances USING btree (event_id, participant_id, "from", status, occurred_at);


--
-- Name: index_attendances_on_participant_from_session_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_participant_from_session_status ON public.attendances USING btree (participant_id, "from", session_id, status, occurred_at);


--
-- Name: index_attendances_on_participant_from_status_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_participant_from_status_occurred_at ON public.attendances USING btree (participant_id, "from", status, occurred_at);


--
-- Name: index_attendances_on_participant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_participant_id ON public.attendances USING btree (participant_id);


--
-- Name: index_attendances_on_scan_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_scan_event_id ON public.attendances USING btree (scan_event_id);


--
-- Name: index_attendances_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendances_on_session_id ON public.attendances USING btree (session_id);


--
-- Name: index_badge_templates_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_badge_templates_on_account_id ON public.badge_templates USING btree (account_id);


--
-- Name: index_badges_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_badges_on_account_id ON public.badges USING btree (account_id);


--
-- Name: index_badges_on_badge_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_badges_on_badge_template_id ON public.badges USING btree (badge_template_id);


--
-- Name: index_badges_on_event_and_category_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_badges_on_event_and_category_uniqueness ON public.badges USING btree (event_id, ticket_category_id) WHERE (ticket_category_id IS NOT NULL);


--
-- Name: index_badges_on_event_default_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_badges_on_event_default_uniqueness ON public.badges USING btree (event_id) WHERE (ticket_category_id IS NULL);


--
-- Name: index_badges_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_badges_on_event_id ON public.badges USING btree (event_id);


--
-- Name: index_badges_on_ticket_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_badges_on_ticket_category_id ON public.badges USING btree (ticket_category_id);


--
-- Name: index_bulk_print_runs_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_print_runs_on_account_id ON public.bulk_print_runs USING btree (account_id);


--
-- Name: index_bulk_print_runs_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_print_runs_on_created_by_id ON public.bulk_print_runs USING btree (created_by_id);


--
-- Name: index_bulk_print_runs_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_print_runs_on_event_id ON public.bulk_print_runs USING btree (event_id);


--
-- Name: index_bulk_print_runs_on_print_station_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_print_runs_on_print_station_id ON public.bulk_print_runs USING btree (print_station_id);


--
-- Name: index_custom_fields_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_custom_fields_on_account_id ON public.custom_fields USING btree (account_id);


--
-- Name: index_custom_fields_on_registration_form_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_custom_fields_on_registration_form_id ON public.custom_fields USING btree (registration_form_id);


--
-- Name: index_email_templates_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_templates_on_account_id ON public.email_templates USING btree (account_id);


--
-- Name: index_email_templates_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_templates_on_event_id ON public.email_templates USING btree (event_id);


--
-- Name: index_email_templates_on_event_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_email_templates_on_event_id_and_kind ON public.email_templates USING btree (event_id, kind);


--
-- Name: index_event_live_stats_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_event_live_stats_on_account_id ON public.event_live_stats USING btree (account_id);


--
-- Name: index_event_live_stats_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_event_live_stats_on_event_id ON public.event_live_stats USING btree (event_id);


--
-- Name: index_event_staff_assignments_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_event_staff_assignments_on_account_id ON public.event_staff_assignments USING btree (account_id);


--
-- Name: index_event_staff_assignments_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_event_staff_assignments_on_event_id ON public.event_staff_assignments USING btree (event_id);


--
-- Name: index_event_staff_assignments_on_event_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_event_staff_assignments_on_event_id_and_user_id ON public.event_staff_assignments USING btree (event_id, user_id);


--
-- Name: index_event_staff_assignments_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_event_staff_assignments_on_user_id ON public.event_staff_assignments USING btree (user_id);


--
-- Name: index_events_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_account_id ON public.events USING btree (account_id);


--
-- Name: index_events_on_account_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_events_on_account_id_and_slug ON public.events USING btree (account_id, slug);


--
-- Name: index_events_on_default_print_station_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_default_print_station_id ON public.events USING btree (default_print_station_id);


--
-- Name: index_export_files_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_export_files_on_account_id ON public.export_files USING btree (account_id);


--
-- Name: index_export_files_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_export_files_on_created_by_id ON public.export_files USING btree (created_by_id);


--
-- Name: index_export_files_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_export_files_on_event_id ON public.export_files USING btree (event_id);


--
-- Name: index_govt_id_import_files_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_govt_id_import_files_on_account_id ON public.govt_id_import_files USING btree (account_id);


--
-- Name: index_govt_id_import_files_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_govt_id_import_files_on_created_by_id ON public.govt_id_import_files USING btree (created_by_id);


--
-- Name: index_govt_id_import_files_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_govt_id_import_files_on_event_id ON public.govt_id_import_files USING btree (event_id);


--
-- Name: index_govt_ids_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_govt_ids_on_account_id ON public.govt_ids USING btree (account_id);


--
-- Name: index_govt_ids_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_govt_ids_on_event_id ON public.govt_ids USING btree (event_id);


--
-- Name: index_govt_ids_on_event_id_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_govt_ids_on_event_id_and_value ON public.govt_ids USING btree (event_id, value);


--
-- Name: index_govt_ids_on_participant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_govt_ids_on_participant_id ON public.govt_ids USING btree (participant_id);


--
-- Name: index_import_files_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_files_on_account_id ON public.import_files USING btree (account_id);


--
-- Name: index_import_files_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_files_on_created_by_id ON public.import_files USING btree (created_by_id);


--
-- Name: index_import_files_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_files_on_event_id ON public.import_files USING btree (event_id);


--
-- Name: index_invoices_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_account_id ON public.invoices USING btree (account_id);


--
-- Name: index_invoices_on_agency_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_agency_id ON public.invoices USING btree (agency_id);


--
-- Name: index_invoices_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoices_on_event_id ON public.invoices USING btree (event_id);


--
-- Name: index_invoices_on_submitted_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_submitted_by_id ON public.invoices USING btree (submitted_by_id);


--
-- Name: index_invoices_on_verified_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_verified_by_id ON public.invoices USING btree (verified_by_id);


--
-- Name: index_live_metric_buckets_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_live_metric_buckets_on_account_id ON public.live_metric_buckets USING btree (account_id);


--
-- Name: index_live_metric_buckets_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_live_metric_buckets_on_event_id ON public.live_metric_buckets USING btree (event_id);


--
-- Name: index_live_metric_buckets_on_event_metric_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_live_metric_buckets_on_event_metric_bucket ON public.live_metric_buckets USING btree (event_id, metric, bucket_at);


--
-- Name: index_notifications_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_account_id ON public.notifications USING btree (account_id);


--
-- Name: index_notifications_on_notifiable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_notifiable ON public.notifications USING btree (notifiable_type, notifiable_id);


--
-- Name: index_oauth_access_grants_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_application_id ON public.oauth_access_grants USING btree (application_id);


--
-- Name: index_oauth_access_grants_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_resource_owner_id ON public.oauth_access_grants USING btree (resource_owner_id);


--
-- Name: index_oauth_access_grants_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON public.oauth_access_grants USING btree (token);


--
-- Name: index_oauth_access_tokens_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_application_id ON public.oauth_access_tokens USING btree (application_id);


--
-- Name: index_oauth_access_tokens_on_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON public.oauth_access_tokens USING btree (refresh_token);


--
-- Name: index_oauth_access_tokens_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON public.oauth_access_tokens USING btree (resource_owner_id);


--
-- Name: index_oauth_access_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON public.oauth_access_tokens USING btree (token);


--
-- Name: index_oauth_applications_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_account_id ON public.oauth_applications USING btree (account_id);


--
-- Name: index_oauth_applications_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_uid ON public.oauth_applications USING btree (uid);


--
-- Name: index_participants_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_participants_on_account_id ON public.participants USING btree (account_id);


--
-- Name: index_participants_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_participants_on_event_id ON public.participants USING btree (event_id);


--
-- Name: index_participants_on_event_id_and_client_participant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_participants_on_event_id_and_client_participant_id ON public.participants USING btree (event_id, client_participant_id);


--
-- Name: index_participants_on_event_id_and_contact_num; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_participants_on_event_id_and_contact_num ON public.participants USING btree (event_id, contact_num);


--
-- Name: index_participants_on_event_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_participants_on_event_id_and_email ON public.participants USING btree (event_id, email);


--
-- Name: index_participants_on_event_id_and_govt_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_participants_on_event_id_and_govt_id ON public.participants USING btree (event_id, govt_id) WHERE ((govt_id)::text <> ''::text);


--
-- Name: index_participants_on_hex_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_participants_on_hex_id ON public.participants USING btree (hex_id);


--
-- Name: index_participants_on_ticket_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_participants_on_ticket_category_id ON public.participants USING btree (ticket_category_id);


--
-- Name: index_print_agents_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_agents_on_account_id ON public.print_agents USING btree (account_id);


--
-- Name: index_print_agents_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_agents_on_event_id ON public.print_agents USING btree (event_id);


--
-- Name: index_print_agents_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_print_agents_on_jti ON public.print_agents USING btree (jti);


--
-- Name: index_print_agents_on_print_station_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_agents_on_print_station_id ON public.print_agents USING btree (print_station_id);


--
-- Name: index_print_jobs_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_jobs_on_account_id ON public.print_jobs USING btree (account_id);


--
-- Name: index_print_jobs_on_bulk_print_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_jobs_on_bulk_print_run_id ON public.print_jobs USING btree (bulk_print_run_id);


--
-- Name: index_print_jobs_on_bulk_print_run_id_and_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_jobs_on_bulk_print_run_id_and_sequence ON public.print_jobs USING btree (bulk_print_run_id, sequence);


--
-- Name: index_print_jobs_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_jobs_on_event_id ON public.print_jobs USING btree (event_id);


--
-- Name: index_print_jobs_on_participant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_jobs_on_participant_id ON public.print_jobs USING btree (participant_id);


--
-- Name: index_print_jobs_on_print_station_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_jobs_on_print_station_id ON public.print_jobs USING btree (print_station_id);


--
-- Name: index_print_stations_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_stations_on_account_id ON public.print_stations USING btree (account_id);


--
-- Name: index_print_stations_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_stations_on_event_id ON public.print_stations USING btree (event_id);


--
-- Name: index_print_stations_on_pairing_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_print_stations_on_pairing_code ON public.print_stations USING btree (pairing_code) WHERE (pairing_code IS NOT NULL);


--
-- Name: index_registration_forms_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_registration_forms_on_account_id ON public.registration_forms USING btree (account_id);


--
-- Name: index_registration_forms_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_registration_forms_on_event_id ON public.registration_forms USING btree (event_id);


--
-- Name: index_scan_events_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_account_id ON public.scan_events USING btree (account_id);


--
-- Name: index_scan_events_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_event_id ON public.scan_events USING btree (event_id);


--
-- Name: index_scan_events_on_event_participant_type_scanned_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_event_participant_type_scanned_at ON public.scan_events USING btree (event_id, participant_id, scan_type, scanned_at);


--
-- Name: index_scan_events_on_participant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_participant_id ON public.scan_events USING btree (participant_id);


--
-- Name: index_scan_events_on_participant_type_scanned_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_participant_type_scanned_at ON public.scan_events USING btree (participant_id, scan_type, scanned_at);


--
-- Name: index_scan_events_on_participant_type_session_scanned_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_participant_type_session_scanned_at ON public.scan_events USING btree (participant_id, scan_type, session_id, scanned_at);


--
-- Name: index_scan_events_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scan_events_on_session_id ON public.scan_events USING btree (session_id);


--
-- Name: index_schedules_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedules_on_account_id ON public.schedules USING btree (account_id);


--
-- Name: index_schedules_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedules_on_event_id ON public.schedules USING btree (event_id);


--
-- Name: index_schedules_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedules_on_session_id ON public.schedules USING btree (session_id);


--
-- Name: index_schedules_on_speaker_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedules_on_speaker_id ON public.schedules USING btree (speaker_id);


--
-- Name: index_session_live_stats_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_session_live_stats_on_account_id ON public.session_live_stats USING btree (account_id);


--
-- Name: index_session_live_stats_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_session_live_stats_on_event_id ON public.session_live_stats USING btree (event_id);


--
-- Name: index_session_live_stats_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_session_live_stats_on_session_id ON public.session_live_stats USING btree (session_id);


--
-- Name: index_sessions_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_account_id ON public.sessions USING btree (account_id);


--
-- Name: index_sessions_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_event_id ON public.sessions USING btree (event_id);


--
-- Name: index_speakers_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_speakers_on_account_id ON public.speakers USING btree (account_id);


--
-- Name: index_speakers_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_speakers_on_event_id ON public.speakers USING btree (event_id);


--
-- Name: index_tenant_domains_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tenant_domains_on_account_id ON public.tenant_domains USING btree (account_id);


--
-- Name: index_tenant_domains_on_domain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenant_domains_on_domain ON public.tenant_domains USING btree (domain);


--
-- Name: index_ticket_categories_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_categories_on_account_id ON public.ticket_categories USING btree (account_id);


--
-- Name: index_ticket_categories_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_categories_on_event_id ON public.ticket_categories USING btree (event_id);


--
-- Name: index_ticket_categories_on_registration_form_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_categories_on_registration_form_id ON public.ticket_categories USING btree (registration_form_id);


--
-- Name: index_ticket_reservations_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_reservations_on_account_id ON public.ticket_reservations USING btree (account_id);


--
-- Name: index_ticket_reservations_on_claim_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ticket_reservations_on_claim_token ON public.ticket_reservations USING btree (claim_token);


--
-- Name: index_ticket_reservations_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_reservations_on_event_id ON public.ticket_reservations USING btree (event_id);


--
-- Name: index_ticket_reservations_on_ticket_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_reservations_on_ticket_category_id ON public.ticket_reservations USING btree (ticket_category_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: print_jobs fk_rails_01cc9771d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_jobs
    ADD CONSTRAINT fk_rails_01cc9771d0 FOREIGN KEY (bulk_print_run_id) REFERENCES public.bulk_print_runs(id);


--
-- Name: bulk_print_runs fk_rails_057556ff5d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_print_runs
    ADD CONSTRAINT fk_rails_057556ff5d FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_staff_assignments fk_rails_061f24f219; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_staff_assignments
    ADD CONSTRAINT fk_rails_061f24f219 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ticket_reservations fk_rails_0779321a7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_reservations
    ADD CONSTRAINT fk_rails_0779321a7a FOREIGN KEY (ticket_category_id) REFERENCES public.ticket_categories(id);


--
-- Name: live_metric_buckets fk_rails_0c8e23a35d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.live_metric_buckets
    ADD CONSTRAINT fk_rails_0c8e23a35d FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: govt_id_import_files fk_rails_0d05a62e1a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_id_import_files
    ADD CONSTRAINT fk_rails_0d05a62e1a FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: govt_id_import_files fk_rails_1436981572; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_id_import_files
    ADD CONSTRAINT fk_rails_1436981572 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: events fk_rails_17c5f28626; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_17c5f28626 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: schedules fk_rails_1a2a830e5d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT fk_rails_1a2a830e5d FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: import_files fk_rails_1bdf7b8f3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_files
    ADD CONSTRAINT fk_rails_1bdf7b8f3b FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: notifications fk_rails_1c0a19e3ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_1c0a19e3ee FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: oauth_applications fk_rails_211c1cecac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications
    ADD CONSTRAINT fk_rails_211c1cecac FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: agency_memberships fk_rails_273f2f9052; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agency_memberships
    ADD CONSTRAINT fk_rails_273f2f9052 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: participants fk_rails_277582be2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT fk_rails_277582be2b FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: attendances fk_rails_2964ee025e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT fk_rails_2964ee025e FOREIGN KEY (scan_event_id) REFERENCES public.scan_events(id);


--
-- Name: session_live_stats fk_rails_2da9181c6a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_live_stats
    ADD CONSTRAINT fk_rails_2da9181c6a FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: oauth_access_grants fk_rails_330c32d8d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT fk_rails_330c32d8d9 FOREIGN KEY (resource_owner_id) REFERENCES public.users(id);


--
-- Name: registration_forms fk_rails_370f9a85da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registration_forms
    ADD CONSTRAINT fk_rails_370f9a85da FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: accounts fk_rails_3727d03534; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_3727d03534 FOREIGN KEY (agency_id) REFERENCES public.agencies(id);


--
-- Name: agency_memberships fk_rails_3bdac11d3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agency_memberships
    ADD CONSTRAINT fk_rails_3bdac11d3b FOREIGN KEY (agency_id) REFERENCES public.agencies(id);


--
-- Name: ticket_reservations fk_rails_3d564f1d49; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_reservations
    ADD CONSTRAINT fk_rails_3d564f1d49 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: badges fk_rails_426a9d13d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT fk_rails_426a9d13d8 FOREIGN KEY (badge_template_id) REFERENCES public.badge_templates(id);


--
-- Name: session_live_stats fk_rails_4466d35e90; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_live_stats
    ADD CONSTRAINT fk_rails_4466d35e90 FOREIGN KEY (session_id) REFERENCES public.sessions(id);


--
-- Name: event_staff_assignments fk_rails_4773054ab1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_staff_assignments
    ADD CONSTRAINT fk_rails_4773054ab1 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: invoices fk_rails_4cfcaef826; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_4cfcaef826 FOREIGN KEY (verified_by_id) REFERENCES public.users(id);


--
-- Name: badges fk_rails_4e7b900548; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT fk_rails_4e7b900548 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: badge_templates fk_rails_515f8054d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badge_templates
    ADD CONSTRAINT fk_rails_515f8054d0 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: account_switches fk_rails_51a6f30384; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_switches
    ADD CONSTRAINT fk_rails_51a6f30384 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: scan_events fk_rails_52eec40412; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT fk_rails_52eec40412 FOREIGN KEY (session_id) REFERENCES public.sessions(id);


--
-- Name: attendances fk_rails_554712257a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT fk_rails_554712257a FOREIGN KEY (participant_id) REFERENCES public.participants(id);


--
-- Name: sessions fk_rails_5599381559; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_5599381559 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: ticket_categories fk_rails_57e1f626f2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_categories
    ADD CONSTRAINT fk_rails_57e1f626f2 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: tenant_domains fk_rails_57f7f0d94b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_domains
    ADD CONSTRAINT fk_rails_57f7f0d94b FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: export_files fk_rails_586fce45ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_files
    ADD CONSTRAINT fk_rails_586fce45ca FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: ticket_reservations fk_rails_5b89783a18; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_reservations
    ADD CONSTRAINT fk_rails_5b89783a18 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: print_jobs fk_rails_5c174e3f62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_jobs
    ADD CONSTRAINT fk_rails_5c174e3f62 FOREIGN KEY (participant_id) REFERENCES public.participants(id);


--
-- Name: import_files fk_rails_5dbe2f79b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_files
    ADD CONSTRAINT fk_rails_5dbe2f79b7 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: live_metric_buckets fk_rails_604ccd39df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.live_metric_buckets
    ADD CONSTRAINT fk_rails_604ccd39df FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: email_templates fk_rails_620c37281c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT fk_rails_620c37281c FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: custom_fields fk_rails_63a869fd87; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT fk_rails_63a869fd87 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: govt_id_import_files fk_rails_64358afee9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_id_import_files
    ADD CONSTRAINT fk_rails_64358afee9 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: print_stations fk_rails_66022c3ff6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_stations
    ADD CONSTRAINT fk_rails_66022c3ff6 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: account_switches fk_rails_66b1620b17; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_switches
    ADD CONSTRAINT fk_rails_66b1620b17 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: badges fk_rails_68a813303d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT fk_rails_68a813303d FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: email_templates fk_rails_6a6ed3c885; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT fk_rails_6a6ed3c885 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: oauth_access_tokens fk_rails_732cb83ab7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT fk_rails_732cb83ab7 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: attendances fk_rails_777eb7170a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT fk_rails_777eb7170a FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: events fk_rails_7ac45dab10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_7ac45dab10 FOREIGN KEY (default_print_station_id) REFERENCES public.print_stations(id);


--
-- Name: print_jobs fk_rails_7affbc829e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_jobs
    ADD CONSTRAINT fk_rails_7affbc829e FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: participants fk_rails_7fb90e9337; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT fk_rails_7fb90e9337 FOREIGN KEY (ticket_category_id) REFERENCES public.ticket_categories(id);


--
-- Name: invoices fk_rails_7ffa025363; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_7ffa025363 FOREIGN KEY (submitted_by_id) REFERENCES public.users(id);


--
-- Name: govt_ids fk_rails_86ed8ec5cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_ids
    ADD CONSTRAINT fk_rails_86ed8ec5cd FOREIGN KEY (participant_id) REFERENCES public.participants(id);


--
-- Name: session_live_stats fk_rails_8713d44924; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_live_stats
    ADD CONSTRAINT fk_rails_8713d44924 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: invoices fk_rails_8c3712adee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_8c3712adee FOREIGN KEY (agency_id) REFERENCES public.agencies(id);


--
-- Name: account_memberships fk_rails_8e0ff21478; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_8e0ff21478 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: event_live_stats fk_rails_9294469d53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_live_stats
    ADD CONSTRAINT fk_rails_9294469d53 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: print_agents fk_rails_950e23e259; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_agents
    ADD CONSTRAINT fk_rails_950e23e259 FOREIGN KEY (print_station_id) REFERENCES public.print_stations(id);


--
-- Name: schedules fk_rails_965f2422fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT fk_rails_965f2422fe FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: print_jobs fk_rails_97a6bde7ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_jobs
    ADD CONSTRAINT fk_rails_97a6bde7ac FOREIGN KEY (print_station_id) REFERENCES public.print_stations(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: speakers fk_rails_9e6f52ae62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.speakers
    ADD CONSTRAINT fk_rails_9e6f52ae62 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: scan_events fk_rails_a4e11069cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT fk_rails_a4e11069cf FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: invoices fk_rails_aa64c7515d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_aa64c7515d FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: sessions fk_rails_ad07c9070c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_ad07c9070c FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: print_jobs fk_rails_ae6f62054d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_jobs
    ADD CONSTRAINT fk_rails_ae6f62054d FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: invoices fk_rails_afb4b1e584; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_afb4b1e584 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: oauth_access_grants fk_rails_b4b53e07b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT fk_rails_b4b53e07b8 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: import_files fk_rails_b5d320435e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_files
    ADD CONSTRAINT fk_rails_b5d320435e FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: speakers fk_rails_b6ad724a8a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.speakers
    ADD CONSTRAINT fk_rails_b6ad724a8a FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: print_agents fk_rails_b6bb770118; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_agents
    ADD CONSTRAINT fk_rails_b6bb770118 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: event_live_stats fk_rails_b9464ab1ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_live_stats
    ADD CONSTRAINT fk_rails_b9464ab1ca FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: scan_events fk_rails_baf8197b7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT fk_rails_baf8197b7a FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: print_stations fk_rails_bcda1f8c06; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_stations
    ADD CONSTRAINT fk_rails_bcda1f8c06 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: registration_forms fk_rails_bd169303b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registration_forms
    ADD CONSTRAINT fk_rails_bd169303b4 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: scan_events fk_rails_bf7c511cdc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT fk_rails_bf7c511cdc FOREIGN KEY (participant_id) REFERENCES public.participants(id);


--
-- Name: event_staff_assignments fk_rails_bff8828e76; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_staff_assignments
    ADD CONSTRAINT fk_rails_bff8828e76 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: govt_ids fk_rails_c108f98fa2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_ids
    ADD CONSTRAINT fk_rails_c108f98fa2 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: schedules fk_rails_c2e315e17d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT fk_rails_c2e315e17d FOREIGN KEY (session_id) REFERENCES public.sessions(id);


--
-- Name: ticket_categories fk_rails_c31749faca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_categories
    ADD CONSTRAINT fk_rails_c31749faca FOREIGN KEY (registration_form_id) REFERENCES public.registration_forms(id);


--
-- Name: account_memberships fk_rails_c33721ecfa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_c33721ecfa FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: print_agents fk_rails_c34bfb43bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_agents
    ADD CONSTRAINT fk_rails_c34bfb43bf FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: badges fk_rails_c61343f571; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT fk_rails_c61343f571 FOREIGN KEY (ticket_category_id) REFERENCES public.ticket_categories(id);


--
-- Name: schedules fk_rails_c69feeea7c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedules
    ADD CONSTRAINT fk_rails_c69feeea7c FOREIGN KEY (speaker_id) REFERENCES public.speakers(id);


--
-- Name: export_files fk_rails_c72035d816; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_files
    ADD CONSTRAINT fk_rails_c72035d816 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: bulk_print_runs fk_rails_c9bd6b4f2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_print_runs
    ADD CONSTRAINT fk_rails_c9bd6b4f2e FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: bulk_print_runs fk_rails_c9fc2e6fec; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_print_runs
    ADD CONSTRAINT fk_rails_c9fc2e6fec FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: attendances fk_rails_cebb463e84; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT fk_rails_cebb463e84 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: attendances fk_rails_e470d5040d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT fk_rails_e470d5040d FOREIGN KEY (session_id) REFERENCES public.sessions(id);


--
-- Name: govt_ids fk_rails_e6a1893200; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.govt_ids
    ADD CONSTRAINT fk_rails_e6a1893200 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: custom_fields fk_rails_e9bd640638; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT fk_rails_e9bd640638 FOREIGN KEY (registration_form_id) REFERENCES public.registration_forms(id);


--
-- Name: bulk_print_runs fk_rails_edf7da98ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_print_runs
    ADD CONSTRAINT fk_rails_edf7da98ee FOREIGN KEY (print_station_id) REFERENCES public.print_stations(id);


--
-- Name: oauth_access_tokens fk_rails_ee63f25419; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT fk_rails_ee63f25419 FOREIGN KEY (resource_owner_id) REFERENCES public.users(id);


--
-- Name: export_files fk_rails_f419e98cf3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_files
    ADD CONSTRAINT fk_rails_f419e98cf3 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: ticket_categories fk_rails_fa44d58f83; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_categories
    ADD CONSTRAINT fk_rails_fa44d58f83 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: participants fk_rails_fc5ec3430a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT fk_rails_fc5ec3430a FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: attendances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendances ENABLE ROW LEVEL SECURITY;

--
-- Name: badge_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.badge_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: badges; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;

--
-- Name: bulk_print_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bulk_print_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: custom_fields; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.custom_fields ENABLE ROW LEVEL SECURITY;

--
-- Name: email_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: event_live_stats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_live_stats ENABLE ROW LEVEL SECURITY;

--
-- Name: event_staff_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_staff_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: export_files; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.export_files ENABLE ROW LEVEL SECURITY;

--
-- Name: govt_id_import_files; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.govt_id_import_files ENABLE ROW LEVEL SECURITY;

--
-- Name: govt_ids; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.govt_ids ENABLE ROW LEVEL SECURITY;

--
-- Name: import_files; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_files ENABLE ROW LEVEL SECURITY;

--
-- Name: live_metric_buckets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.live_metric_buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: participants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.participants ENABLE ROW LEVEL SECURITY;

--
-- Name: print_agents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.print_agents ENABLE ROW LEVEL SECURITY;

--
-- Name: print_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.print_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: print_stations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.print_stations ENABLE ROW LEVEL SECURITY;

--
-- Name: registration_forms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.registration_forms ENABLE ROW LEVEL SECURITY;

--
-- Name: scan_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.scan_events ENABLE ROW LEVEL SECURITY;

--
-- Name: schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: session_live_stats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.session_live_stats ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: speakers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.speakers ENABLE ROW LEVEL SECURITY;

--
-- Name: attendances tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.attendances USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: badge_templates tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.badge_templates USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: badges tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.badges USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: bulk_print_runs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bulk_print_runs USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: custom_fields tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.custom_fields USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: email_templates tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.email_templates USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: event_live_stats tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.event_live_stats USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: event_staff_assignments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.event_staff_assignments USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.events USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: export_files tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.export_files USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: govt_id_import_files tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.govt_id_import_files USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: govt_ids tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.govt_ids USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: import_files tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_files USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: live_metric_buckets tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.live_metric_buckets USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: notifications tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.notifications USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: participants tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.participants USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: print_agents tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.print_agents USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: print_jobs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.print_jobs USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: print_stations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.print_stations USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: registration_forms tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.registration_forms USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: scan_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.scan_events USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: schedules tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.schedules USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: session_live_stats tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.session_live_stats USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: sessions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sessions USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: speakers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.speakers USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: ticket_categories tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ticket_categories USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: ticket_reservations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ticket_reservations USING ((account_id = (current_setting('app.current_account_id'::text, true))::uuid));


--
-- Name: ticket_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ticket_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: ticket_reservations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ticket_reservations ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260719070000'),
('20260719060300'),
('20260719060200'),
('20260719060100'),
('20260719060000'),
('20260719050300'),
('20260719050200'),
('20260719050100'),
('20260719050000'),
('20260719000005'),
('20260719000004'),
('20260719000003'),
('20260719000002'),
('20260719000001'),
('20260718130000'),
('20260718120000'),
('20260718110300'),
('20260718110200'),
('20260718110100'),
('20260718110000'),
('20260718100500'),
('20260718100400'),
('20260718100300'),
('20260718100200'),
('20260718100100'),
('20260718100000'),
('20260718090000'),
('20260717182828'),
('20260717182827'),
('20260717175558'),
('20260717170635'),
('20260717160019'),
('20260717160018'),
('20260717160017'),
('20260717144711'),
('20260717063742'),
('20260716163415'),
('20260716161439'),
('20260716145429'),
('20260716144904'),
('20260712191046'),
('20260712184119'),
('20260712184118'),
('20260712184117'),
('20260712180616'),
('20260712180615'),
('20260712180614'),
('20260712180613'),
('20260712180612'),
('20260712172323'),
('20260712172322'),
('20260712172321'),
('20260712053054'),
('20260712053032'),
('20260712044746'),
('20260711181036'),
('20260711170512'),
('20260711170511'),
('20260711170449'),
('20260711170422'),
('20260711170348'),
('20260711170325'),
('20260711170110'),
('20260711154921'),
('20260711154853'),
('20260711154833'),
('20260711153549'),
('20260711151423'),
('20260711142604'),
('20260711132926'),
('20260711120609'),
('20260711120407'),
('20260711100510'),
('20260711100439'),
('20260710162528'),
('20260710162527'),
('20260710162526'),
('20260710162501'),
('20260710162342');

