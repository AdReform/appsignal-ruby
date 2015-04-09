require 'spec_helper'

describe "Sequel integration", if: sequel_present? do
  let(:file) { File.expand_path('lib/appsignal/integrations/sequel.rb') }
  let(:db)   { Sequel.sqlite }

  before do
    load file
    start_agent
  end

  context "with Sequel" do
    before { Appsignal::Transaction.create('uuid', 'test') }

    it "should instrument queries" do
      expect { db['SELECT 1'].all }
        .to change { Appsignal::Transaction.current.events.empty? }
        .from(true).to(false)
    end
  end
end
