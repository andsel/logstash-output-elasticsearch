require_relative "../../../spec/es_spec_helper"
require "logstash/outputs/elasticsearch"

describe "join type field", :integration => true do

  shared_examples "a join field based parent indexer" do
    let(:index) { 10.times.collect { rand(10).to_s }.join("") }

    let(:type) { "_doc" }

    let(:event_count) { 10000 + rand(500) }
    let(:parent) { "not_implemented" }
    let(:config) { "not_implemented" }
    let(:parent_id) { "test" }
    let(:join_field) { "join_field" }
    let(:parent_relation) { "parent_type" }
    let(:child_relation) { "child_type" }
    let(:default_headers) {
      {"Content-Type" => "application/json"}
    }
    subject { LogStash::Outputs::ElasticSearch.new(config) }

    before do
      # Add mapping and a parent document
      index_url = "http://#{get_host_port()}/#{index}"

      properties = {
        "properties" => {
          join_field => {
            "type" => "join",
            "relations" => { parent_relation => child_relation }
          }
        }
      }

      mapping = { "mappings" => properties}

      Manticore.put("#{index_url}", {:body => mapping.to_json, :headers => default_headers}).call
      pdoc = { "message" => "ohayo", join_field => parent_relation }
      Manticore.put("#{index_url}/#{type}/#{parent_id}", {:body => pdoc.to_json, :headers => default_headers}).call

      subject.register
      subject.multi_receive(event_count.times.map { LogStash::Event.new("link_to" => parent_id, "message" => "Hello World!", join_field => child_relation) })
    end


    it "ships events" do
      index_url = "http://#{get_host_port()}/#{index}"

      Manticore.post("#{index_url}/_refresh").call

      # Wait until all events are available.
      Stud::try(10.times) do
        query = { "query" => { "has_parent" => { "parent_type" => parent_relation, "query" => { "match_all" => { } } } } }
        response = Manticore.post("#{index_url}/_count", {:body => query.to_json, :headers => default_headers})
        data = response.body
        result = LogStash::Json.load(data)
        cur_count = result["count"]
        expect(cur_count).to eq(event_count)
      end
    end
  end

  describe "(http protocol) index events with static parent" do
    it_behaves_like 'a join field based parent indexer' do
      let(:config) {
        {
          "hosts" => get_host_port,
          "index" => index,
          "parent" => parent_id,
          "document_type" => type,
          "join_field" => join_field,
          "manage_template" => false
        }
      }
    end
  end

  describe "(http_protocol) index events with fieldref in parent value" do
    it_behaves_like 'a join field based parent indexer' do
      let(:config) {
        {
          "hosts" => get_host_port,
          "index" => index,
          "parent" => "%{link_to}",
          "document_type" => type,
          "join_field" => join_field,
          "manage_template" => false
        }
      }
    end
  end
end
