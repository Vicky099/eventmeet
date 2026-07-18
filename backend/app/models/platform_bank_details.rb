# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6): shown in the tenant's
# "Mark as Paid" modal so they know where to actually send the NEFT/IMPS transfer before
# submitting a UTR. One fixed platform-level bank account (not per-tenant, not admin-editable from
# a settings screen — this app has no such settings UI, and building one wasn't asked for) — plain
# ENV-overridable constants, same "clearly-flagged placeholder, not real confirmed data" treatment
# already established elsewhere in this app: no real bank details exist anywhere in
# requirement.md, so these are illustrative until the platform operator provides real ones (set the
# matching ENV vars in production; the fallback values below only show up in dev/test).
module PlatformBankDetails
  ACCOUNT_NAME = ENV.fetch("PLATFORM_BANK_ACCOUNT_NAME", "EventMeet Platform Pvt Ltd")
  ACCOUNT_NUMBER = ENV.fetch("PLATFORM_BANK_ACCOUNT_NUMBER", "000000000000")
  IFSC_CODE = ENV.fetch("PLATFORM_BANK_IFSC_CODE", "PLAT0000000")
  BANK_NAME = ENV.fetch("PLATFORM_BANK_NAME", "Placeholder Bank")
  BRANCH = ENV.fetch("PLATFORM_BANK_BRANCH", "Placeholder Branch")
end
