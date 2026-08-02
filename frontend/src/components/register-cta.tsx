import type { TicketCategorySchema } from "@/lib/server/rails";

// doc/event_page_templates_plan.md revisit — replaces registration-modal.tsx's old floating
// button-that-opens-a-modal (deleted; registration is a real page now, not a modal). A plain
// server-renderable link — no client-side state needed at all now that there's no modal to open.
export function RegisterCta({
  href,
  ticketCategories,
}: {
  href: string;
  ticketCategories: TicketCategorySchema[];
}) {
  if (ticketCategories.length === 0) return null;

  return (
    <a
      href={href}
      className="fixed bottom-6 right-6 z-40 rounded-full bg-blue-600 px-6 py-3 font-semibold text-white shadow-lg hover:bg-blue-700"
    >
      Register
    </a>
  );
}
