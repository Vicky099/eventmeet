module Hosting
  # Routing constraint: matches only the bare platform_domain apex — Platform Console territory
  # (requirement.md §4.3). Used to wrap the SuperAdmin:: routes in config/routes.rb so tenant
  # requests can never reach a SuperAdmin:: controller by construction, not just by convention.
  class ApexConstraint
    def matches?(request)
      Resolver.new(request.host).apex?
    end
  end
end
