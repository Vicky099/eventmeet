# Current (app/models/current.rb) is reset automatically between real requests via Rails'
# executor, but model/service specs that set it directly need an explicit reset so one example's
# Current.account never bleeds into the next.
RSpec.configure do |config|
  config.after do
    Current.reset
  end
end
