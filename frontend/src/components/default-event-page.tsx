import type { PublicEvent } from "@/lib/server/rails";

// doc/public_event_site_options.md's Confirmed decision #5: the fallback page lives here in
// Next.js, not Rails — shown whenever a published event has no custom HTML stored, or (with no
// `event` prop at all) whenever the event isn't published yet, deliberately withholding real
// event details in that second case since an unpublished event hasn't been announced.
export function DefaultEventPage({ event }: { event?: PublicEvent }) {
  if (!event) {
    return (
      <div className="mx-auto max-w-2xl px-6 py-24 text-center">
        <h1 className="text-2xl font-semibold text-slate-900">
          This event isn&apos;t open yet
        </h1>
        <p className="mt-2 text-slate-600">
          Check back soon — registration will open once the organizer
          publishes this event.
        </p>
      </div>
    );
  }

  const starts = new Date(event.starts_at);
  const ends = new Date(event.ends_at);

  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <h1 className="text-3xl font-bold text-slate-900">{event.name}</h1>
      <p className="mt-2 text-slate-600">
        {starts.toLocaleString()} – {ends.toLocaleString()}
      </p>
      {event.address && <p className="mt-1 text-slate-600">{event.address}</p>}
      {event.meeting_link && (
        <p className="mt-1">
          <a className="text-blue-600 underline" href={event.meeting_link}>
            Join online
          </a>
        </p>
      )}
      {event.description && (
        <p className="mt-6 whitespace-pre-line text-slate-700">
          {event.description}
        </p>
      )}
    </div>
  );
}
