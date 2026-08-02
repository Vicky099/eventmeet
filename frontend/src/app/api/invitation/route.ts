import { NextResponse } from "next/server";
import {
  resolveDomain,
  resolveDomainForAccountSlug,
  fetchInvitationPdf,
} from "@/lib/server/rails";

// requirement.md revisit: "post registration ... download button ... invitation PDF" — a plain
// GET so this can be a real `<a href="/api/invitation?...">` download link (native browser
// download via Content-Disposition below), not a fetch+blob dance. Query string, not a JSON body
// (unlike /api/register) — a GET request has no body, and this needs to work as a bare link.
export async function GET(request: Request) {
  const url = new URL(request.url);
  const slug = url.searchParams.get("slug");
  const hexId = url.searchParams.get("hexId");
  const accountSlug = url.searchParams.get("accountSlug") ?? undefined;

  if (!slug || !hexId) {
    return NextResponse.json({ error: "missing_params" }, { status: 400 });
  }

  // Same accountSlug-vs-Host branch /api/register already uses — see that route's own comment.
  const resolution = accountSlug
    ? await resolveDomainForAccountSlug(accountSlug)
    : await resolveDomain(request.headers.get("host") ?? "");

  if (!resolution) {
    return NextResponse.json({ error: "unknown_host" }, { status: 404 });
  }

  const result = await fetchInvitationPdf(resolution, slug, hexId);
  if (!result.ok || !result.bytes) {
    return NextResponse.json({ error: "not_found" }, { status: result.status || 404 });
  }

  return new NextResponse(result.bytes, {
    status: 200,
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="invitation-${hexId}.pdf"`,
    },
  });
}
