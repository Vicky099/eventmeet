export default function Home() {
  return (
    <div className="flex flex-1 items-center justify-center px-6 py-24 text-center">
      <p className="text-slate-500">
        xEvent public site — visit a specific event at{" "}
        <code className="rounded bg-slate-100 px-1.5 py-0.5">
          /events/[tenantSlug]/[eventSlug]
        </code>{" "}
        on this shared domain, or{" "}
        <code className="rounded bg-slate-100 px-1.5 py-0.5">/events/[eventSlug]</code>{" "}
        on a tenant&apos;s own subdomain (
        <code className="rounded bg-slate-100 px-1.5 py-0.5">
          {"{tenant}."}
          {"{platform_domain}"}
        </code>
        ) or verified custom domain.
      </p>
    </div>
  );
}
