require "rails_helper"

RSpec.describe Currency do
  describe ".symbol_for" do
    it "returns the known symbol for a supported code" do
      expect(Currency.symbol_for("INR")).to eq("₹")
      expect(Currency.symbol_for("USD")).to eq("$")
    end

    it "falls back to the code itself for an unknown currency" do
      expect(Currency.symbol_for("XYZ")).to eq("XYZ")
    end
  end
end
