require "rails_helper"

RSpec.describe Importer::Oklahoma::WellRecords, type: :service do
  let(:file_prefix) { "file://#{Rails.root}/" }

  subject do
    Importer::Oklahoma::WellRecords.new(starts_at: Date.current)
  end

  after(:each) do
    subject.close_browser
  end

  context "Stage 1" do
    before(:each) do
      uri = "#{file_prefix}#{file_fixture("Stage_1.htm")}"

      allow(subject).to receive(:uri).and_return(uri)

      subject.goto_uri
    end

    describe "#fill_dates" do
      it "fills certain fields with specific dates" do
        subject.fill_dates

        field_starts_at = subject.send(:browser).input(name: "txtScanDate").value
        field_ends_at = subject.send(:browser).input(name: "txtScanDateTo").value

        expect(subject.starts_at.strftime("%m/%d/%Y")).to eq field_starts_at
        expect(subject.ends_at.strftime("%m/%d/%Y")).to eq field_ends_at
      end
    end

    describe "#submit_form" do
      it "submits the form" do
        uri_target = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        subject.submit_form

        expect(subject.send(:browser).table).to be_exists
        expect(subject.send(:browser).url).to eq(uri_target)
      end
    end
  end

  context "Stage 2" do
    before(:each) do
      uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

      allow(subject).to receive(:uri).and_return(uri)

      subject.goto_uri
    end

    describe "#run" do
      before(:each) do
        allow(subject).to receive(:download_pdf)
        allow(subject).to receive(:upload_pdf)
      end

      it "saves all rows into db" do
        count_of_documents = subject.count_of_documents

        subject.run

        expect(OklahomaWellRecord.count).to eq count_of_documents
      end

      it "uploads all of pdf to S3" do
        count_of_documents = subject.count_of_documents

        expect(subject).to receive(:upload_pdf).exactly(count_of_documents).times

        subject.run
      end

      it "saves rows with not nil dates" do
        subject.run

        owr = OklahomaWellRecord.take

        expect(owr.effective_date).to be_a Date
        expect(owr.scan_date).to be_a Date
      end

      it "closes browser if job is done" do
        expect(subject).to receive(:close_browser).at_least(:once)

        subject.run
      end
    end

    describe "#count_of_pages" do
      it "returns number of pages of the table" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        expect(subject.count_of_pages).to be_an Integer
        expect(subject.count_of_pages).to eq 2
      end
    end

    describe "#page_link_by" do
      before(:each) do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri
      end

      context "when links exists" do
        it "does not return link, if we are on this page" do
          link = subject.page_link_by(1)

          expect(link).to_not be_exist
        end

        it "returns link of table page by page number" do
          link = subject.page_link_by(2)

          expect(link).to be_exist
        end
      end
    end

    describe "#next_pages_link" do
      context "when link is exists" do
        it "returns link with '...'" do
          uri = "#{file_prefix}#{file_fixture("Stage_4.htm")}"

          allow(subject).to receive(:uri).and_return(uri)

          subject.goto_uri

          expect(subject.next_pages_link.text).to eq "..."
          expect(subject.next_pages_link).to be_exist
        end
      end

      context "when link does not exist" do
        it "not raises error" do
          uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

          allow(subject).to receive(:uri).and_return(uri)

          subject.goto_uri

          expect(subject.next_pages_link).to_not be_exist
        end
      end
    end

    describe "#table" do
      it "returns table" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        expect(subject.table.id).to eq "DataGrid1"
        expect(subject.table).to be_exist
      end
    end

    describe "#get_numbers_of_pages" do
      it "returns array of pages numbers" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        numbers = subject.get_numbers_of_pages

        expect(numbers).to be_a Array
        expect(numbers).to include(a_kind_of(String))
        expect(numbers).to eq(["1", "2"])
      end
    end

    describe "#headers" do
      it "returns table headers" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        headers = %w(ID Form Legal_Location API Well_Name Operator_# Eff/Test_Date ScanDate)

        expect(subject.headers).to eq headers
      end
    end

    describe "#cells_text_of_row" do
      it "returns array with text of row cells" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        row = subject.send(:table).rows[3]
        text =
          [
            "5784237", "SURVEY", "0219N12W N2 NW NW NW", "01124028",
            "MAJOR 19-12-02 1H", " ", "8/28/2018", "7/8/2019"
          ]

        expect(subject.cells_text_of_row(row)).to eq text
      end
    end

    describe "#pdf_url" do
      it "returns pdf url of row" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        row = subject.table.rows[3]
        pdf_url = "http://imaging.occeweb.com/OG/Well%20Records/005842AD.pdf"

        expect(subject.pdf_url(row)).to eq pdf_url
      end
    end

    describe "#table_rows" do
      it "returns rows without headers" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        rows = subject.table_rows
        first_row = rows.first.cells.map(&:text)

        expected_text =
          [
            "5784236", "1002C", "0219N12W N2 NW NW NW", "01124028",
            "MAJOR 19-12-02 1H", " ", "8/5/2018", "7/8/2019"
          ]

        expect(first_row).to eq expected_text
      end
    end

    describe "#row_params" do
      it "returns row params" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri

        row = subject.table.rows[3]
        params = subject.row_params(row)
        expected_params =
          {
            "filing_id"=>"5784237",
            "document_type"=>"SURVEY",
            "legal_location"=>"0219N12W N2 NW NW NW",
            "api"=>"01124028",
            "well_name"=>"MAJOR 19-12-02 1H",
            "operator_number"=>" ",
            "effective_date"=>"8/28/2018",
            "scan_date"=>"7/8/2019",
          }

        expect(params).to eq expected_params
      end
    end

    describe "#close_browser" do
      it "closes browser" do
        uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        allow(subject).to receive(:uri).and_return(uri)

        subject.goto_uri
        subject.close_browser

        expect(subject.send(:browser)).to_not be_exist
      end
    end
  end

  context "Other" do
    describe "#uri" do
      it "returns correct uri" do
        correct_uri = "http://imaging.occeweb.com/imaging/OGWellRecords.aspx"

        expect(subject.uri).to eq correct_uri
      end

      it "returns string" do
        expect(subject.uri).to be_a String
      end
    end

    describe "#format_date" do
      it "returns a date with a specific format" do
        date = Date.parse("2019-07-09")

        expect(subject.send(:format_date, date)).to eq "07/09/2019"
      end
    end

    describe "#strpdate" do
      it "returns parsed date with certain format" do
        date = "07/09/2019"

        expect(subject.send(:strpdate, date)).to eq Date.parse("2019-07-09")
      end
    end

    describe "download_pdf" do
      it "downloads pdf file" do
        url = "#{Rails.root}/#{file_fixture("005842AD.pdf")}"
        file = subject.download_pdf(url)

        expect(file.size).to_not be_nil
        expect(file.size).to_not be_zero
      end
    end

    describe "#upload_pdf" do
      it "uploads pdf to S3" do
        owr = double("owr", api: "123", document_type: "456", filing_id: "789", document_url: "path")
        file = double("file", read: "str")

        expect(subject.send(:client)).to receive(:put_object).at_least(:once) do |args|
          expect(args[:key]).to end_with "123_456_789.pdf"
          expect(args[:content_type]).to eq "application/pdf"
        end

        subject.upload_pdf(file, owr)
      end
    end

    describe "#browser" do
      it "returns instance of browser" do
        expect(subject.send(:browser)).to be_kind_of(Watir::Browser)
      end

      it "returns chrome browser" do
        expect(subject.send(:browser).driver.browser).to be(:chrome)
      end
    end

    describe "#goto_uri" do
      it "goes to certain url" do
        url = "http://imaging.occeweb.com/imaging/OGWellRecords.aspx"

        expect(subject.send(:browser)).to receive(:goto).with(url)

        subject.goto_uri
      end
    end
  end
end
