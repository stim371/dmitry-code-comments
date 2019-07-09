require 'rails_helper'

RSpec.describe Importer::Oklahoma::WellRecords, type: :service do
  subject do
    obj = Importer::Oklahoma::WellRecords.new(starts_at: Date.current - 2.days)
    obj.send(:goto_uri)
    obj.send(:fill_dates)
    obj.send(:submit_form)
    obj
  end

  after(:each) do
    subject.send(:close_browser)
  end

  describe '#run' do
    it 'starts the parser' do
      expect(subject).to receive(:goto_uri).at_least(:once)
      expect(subject).to receive(:fill_dates).at_least(:once)
      expect(subject).to receive(:submit_form).at_least(:once)
      expect(subject).to receive(:collect_rows).at_least(:once)
      expect(subject).to receive(:close_browser).at_least(:once)

      subject.send(:run)
    end
  end

  describe '#browser' do
    it 'returns instance of browser' do
      expect(subject.send(:browser)).to be_kind_of(Watir::Browser)
    end

    it 'returns chrome browser' do
      expect(subject.send(:browser).driver.browser).to be(:chrome)
    end
  end

  describe '#goto_uri' do
    it 'goes to certain url' do
      expect(subject.send(:goto_uri).to_s).to eq("http://imaging.occeweb.com/imaging/OGWellRecords.aspx")
    end
  end

  describe '#uri' do
    it 'returns correct uri' do
      correct_uri = "http://imaging.occeweb.com/imaging/OGWellRecords.aspx"

      expect(subject.send(:uri)).to eq correct_uri
    end

    it 'returns string' do
      expect(subject.send(:uri)).to be_a String
    end
  end

  describe '#format_date' do
    it 'returns a date with a specific format' do
      date = Date.parse("2019-07-09")

      expect(subject.send(:format_date, date)).to eq "07/09/2019"
    end
  end

  describe '#fill_dates' do
    it 'fills certain fields with specific dates' do
      field_starts_at = subject.send(:browser).input(name: "txtScanDate").value
      field_ends_at = subject.send(:browser).input(name: "txtScanDateTo").value

      expect(subject.starts_at.strftime("%m/%d/%Y")).to eq field_starts_at
      expect(subject.ends_at.strftime("%m/%d/%Y")).to eq field_ends_at
    end
  end

  describe '#submit_form' do
    it 'submits the form' do
      expect(subject.send(:browser).table).to be_exists
    end
  end

  describe '#count_of_pages' do
    it 'returns number of pages of the table' do
      expect(subject.send(:count_of_pages)).to be_an Integer
    end
  end

  describe '#page_link_by' do
    context 'when links exists' do
      it 'does not return link, if we are on this page' do
        link = subject.send(:page_link_by, 1)

        expect(link).to_not be_exist
      end

      it 'returns link of table page by page number' do
        link = subject.send(:page_link_by, 2)

        expect(link).to be_exist
      end
    end
  end

  describe '#next_pages_link' do
    before(:each) do
      subject.send(:goto_uri)
      subject.send(:fill_dates)
      subject.send(:submit_form)
    end

    context 'when link is exists' do
      subject { Importer::Oklahoma::WellRecords.new(starts_at: Date.current - 30.days) }

      it 'returns link with "..."' do
        expect(subject.send(:next_pages_link).text).to eq "..."
        expect(subject.send(:next_pages_link)).to be_exist
      end
    end

    context 'when link does not exist' do
      subject { Importer::Oklahoma::WellRecords.new(starts_at: Date.current) }

      it 'not raises error' do
        expect(subject.send(:next_pages_link)).to_not be_exist
      end
    end
  end

  describe '#table' do
    it 'returns table' do
      expect(subject.send(:table).id).to eq "DataGrid1"
      expect(subject.send(:table)).to be_exist
    end
  end

  describe '#get_numbers_of_pages' do
    it 'returns array of pages numbers' do
      numbers = subject.send(:get_numbers_of_pages)
      expect(numbers).to be_a Array
      expect(numbers).to include(a_kind_of(String))
    end
  end

  describe '#headers' do
    it 'returns table headers' do
      headers = %w(ID Form Legal_Location API Well_Name Operator_# Eff/Test_Date ScanDate)

      expect(subject.send(:headers)).to eq headers
    end
  end

  describe '#cells_text_of_row' do
    it 'returns array with text of row cells' do
      row = subject.send(:table).rows[3]
      text = row.cells.map(&:text)

      expect(subject.send(:cells_text_of_row, row)).to eq text
    end
  end

  describe '#strpdate' do
    it 'returns parsed date with certain format' do
      date = "07/09/2019"

      expect(subject.send(:strpdate, date)).to eq Date.parse("2019-07-09")
    end
  end

  describe '#pdf_url' do
    it 'returns pdf url of row' do
      row = subject.send(:table).rows[3]

      expect(subject.send(:pdf_url, row)).to end_with ".pdf"
    end
  end

  describe '#table_rows' do
    it 'returns rows without headers' do
      rows = subject.send(:table_rows)
      first_row = rows.first.cells.first.text

      expect(first_row).to_not eq "ID"
    end
  end

  describe '#collect_rows' do
    let(:count_of_documents) { subject.send(:count_of_documents) }

    before(:each) do
      # allow_any_instance_of(OklahomaWellRecord).to receive(:save)
      allow(subject).to receive(:download_pdf)
      allow(subject).to receive(:upload_pdf)
    end

    it 'saves all rows into db' do
      subject.send(:collect_rows)

      expect(OklahomaWellRecord.count).to eq count_of_documents
    end

    it 'uploads all of pdf to S3' do
      expect(subject).to receive(:upload_pdf).exactly(count_of_documents).times

      subject.send(:collect_rows)
    end
  end

  describe '#upload_pdf' do
    it "uploads pdf to S3" do
      owr = double("owr", api: "123", document_type: "456", filing_id: "789", document_url: "path")

      expect(subject.send(:client)).to receive(:put_object).at_least(:once) do |arg|
        expect(arg[:key]).to end_with '123\_456\_789.pdf'
        expect(arg[:content_type]).to eq "application/pdf"
      end

      subject.send(:upload_pdf, owr)
    end
  end

  describe '#row_params' do
    it 'returns row params' do
      row = subject.send(:table).rows[3]
      params = subject.send(:row_params, row)

      expect(params).to be_a Hash

      Importer::Oklahoma::WellRecords::RENAME.values.each do |key|
        expect(params).to have_key key
      end
    end
  end

  describe '#close_browser' do
    it 'closes browser' do
      subject.send(:close_browser)

      expect(subject.send(:browser)).to_not be_exist
    end
  end
end
