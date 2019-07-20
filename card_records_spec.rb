require "rails_helper"

RSpec.describe NewMexico::CardRecords, type: :service do
  let(:file_prefix) { "file://#{Rails.root}/" }

  after(:each) do
    subject.close_browser
  end

  context "Other" do
    describe "#uri" do
      it "returns correct uri" do
        correct_uri = "https://wwwapps.emnrd.state.nm.us/ocd/ocdpermitting/OperatorData/PermitStatusParameters.aspx"

        expect(subject.uri).to eq correct_uri
      end
    end

    describe "#filename" do
      it "returns the output file name" do
        file_url = "http://ocdimage.emnrd.state.nm.us/imaging/filestore/santafe/wf/20190716/30025053060000_07_16_2019_03_01_48.pdf"

        filename =
          subject.filename(
            file_url: file_url,
            document_type: "Type",
            permit_id: "Permit_id",
            filing_date: "2019-07-17"
          )

        expect(filename).to eq "30025053060000_07_16_2019_03_01_48_Type_Permit_id_2019-07-17.pdf"
      end
    end

    describe "download_pdf" do
      let(:url) { "#{Rails.root}/#{file_fixture("005842AD.pdf")}" }

      it "downloads pdf file" do
        file = subject.download_pdf(url)

        expect(file.size).to_not be_zero
      end

      context "when download was failure" do
        it "raises error" do
          allow(subject).to receive(:open).and_raise("Error")

          expect { subject.download_pdf(url) }.to raise_error "Error"
        end
      end
    end

    describe "#upload_pdf" do
      it "uploads pdf to S3" do
        filename = "30025053060000_07_16_2019_03_01_48_Type_Permit_id_2019-07-17.pdf"
        file = double("file", read: "str")

        expect(subject.send(:client)).to receive(:put_object).at_least(:once) do |args|
          expect(args[:key]).to end_with filename
          expect(args[:content_type]).to eq "application/pdf"
        end

        subject.upload_pdf(file, filename)
      end
    end
  end

  context "Stage 1" do
    before(:each) do
      uri = "#{file_prefix}#{file_fixture("Stage_1.htm")}"

      allow(subject).to receive(:uri).and_return(uri)

      subject.goto(uri)
    end

    describe "#submit_form" do
      it "submits the form" do
        uri_target = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

        subject.submit_form

        expect(subject.send(:browser).table(id: "ctl00_ctl00__main_main_gvResults")).to be_exists
        expect(subject.send(:browser).url).to eq(uri_target)
      end
    end

    describe "#fill_form" do
      it "fills form" do
        subject.fill_form
        current_year = Date.current.strftime("%Y")

        permit_type = subject.send(:browser).select(name: "ctl00$ctl00$_main$main$ddlPermitType").value
        permit_status = subject.send(:browser).select(name: "ctl00$ctl00$_main$main$ddlPermitStatus").value
        status_year = subject.send(:browser).select(name: "ctl00$ctl00$_main$main$ddlStatusYear").value

        expect(permit_type).to eq "All"
        expect(permit_status).to eq "All"
        expect(status_year).to eq current_year
      end
    end
  end

  context "Stage 2" do
    before(:each) do
      uri = "#{file_prefix}#{file_fixture("Stage_2.htm")}"

      allow(subject).to receive(:uri).and_return(uri)

      subject.goto(uri)
    end

    describe "#run" do
      let(:stage_four_file) { "#{file_prefix}#{file_fixture("Stage_4.htm")}" }
      let(:count_of_pages) { 50 }

      before(:each) do
        allow(subject).to receive(:download_pdf)
        allow(subject).to receive(:upload_pdf)
        allow(subject).to receive(:goto)
        allow(subject).to receive(:fill_form)
        allow(subject).to receive(:submit_form)
        allow_any_instance_of(Watir::Row).to receive(:link).and_return(double(href: stage_four_file))
      end

      it "saves all rows and info tables into db" do
        subject.run

        expect(NewMexicoQueryRecord.count).to eq count_of_pages
        expect(NewMexicoCardRecord.count).to eq count_of_pages
      end

      it "saves rows and tables with correct parameters" do
        subject.run

        nm_query_record = NewMexicoQueryRecord.first
        nm_query_record_expected_params =
          {
            "filing_id" => "269757",
            "document_type" => "Tubing",
            "document_comment" => "FASKEN OIL & RANCH LTD[151416]\nDENTON SWD #003\n30-025-05306",
            "document_status" => "APPROVED",
            "scan_date" => Date.parse("2019-07-16")
          }

        nm_card_record = NewMexicoCardRecord.first
        nm_card_record_expected_params =
          {
            "permit_id" => "269757",
            "operator_name" => "FASKEN OIL & RANCH LTD [151416]",
            "well_name_full" => "DENTON SWD #003",
            "location" => "M-12-15S-37E",
            "previous_name" => "",
            "new_name" => "",
          }

        expect(nm_query_record.attributes).to include nm_query_record_expected_params
        expect(nm_card_record.attributes).to include nm_card_record_expected_params
      end

      it "uploads all of pdf to S3" do
        expect(subject).to receive(:upload_pdf).exactly(count_of_pages).times

        subject.run
      end
    end

    describe "#count_of_pages" do
      it "returns count of table pages" do
        expect(subject.count_of_pages).to eq 2
      end
    end

    describe "#rows" do
      it "returns rows without headers" do
        headers = ["Id", "Type", "Description", "Status", "Status Date"]

        first_row = subject.rows.first
        row_text = first_row.cells.map(&:text)

        expect(row_text).to_not eq headers
      end
    end

    describe "#headers" do
      it "returns table headers" do
        headers = ["Id", "Type", "Description", "Status", "Status Date"]

        expect(subject.headers).to eq headers
      end
    end

    describe "#cells_text_of_row" do
      it "returns text of cells of row" do
        row = subject.rows.first
        expected_text =
          [
            "269757",
            "Tubing",
            "FASKEN OIL & RANCH LTD[151416]\nDENTON SWD #003\n30-025-05306",
            "APPROVED",
            "7/16/2019"
          ]

        expect(subject.cells_text_of_row(row)).to eq expected_text
      end
    end

    describe "#row_params" do
      it "returns hash of params of row" do
        row = subject.rows.first
        expected_params =
          {
            "filing_id" => "269757",
            "document_type" => "Tubing",
            "document_comment" => "FASKEN OIL & RANCH LTD[151416]\nDENTON SWD #003\n30-025-05306",
            "document_status" => "APPROVED",
            "scan_date" => "7/16/2019"
          }

        expect(subject.row_params(row)).to eq expected_params
      end
    end
  end

  context "Stage 4" do
    before(:each) do
      uri = "#{file_prefix}#{file_fixture("Stage_4.htm")}"

      allow(subject).to receive(:uri).and_return(uri)

      subject.goto(uri)
    end


    describe "#well_files_url" do
      context "when well files button exists" do
        it "returns url" do
          url = "http://ocdimage.emnrd.state.nm.us/imaging/WellFileView.aspx?RefType=WF&RefID=30025053060000"

          expect(subject.well_files_url).to eq url
        end
      end

      context "when well files button does not exist" do
        it "returns empty string" do
          allow(subject.send(:browser)).to receive(:button).and_return(double(exists?: false))

          expect(subject.well_files_url).to eq ""
        end
      end
    end

    describe "#location_url" do
      it 'returns url of first entry in Forms fieldset' do
        url = "http://ocdimage.emnrd.state.nm.us/imaging/filestore/santafe/wf/20190716/30025053060000_07_16_2019_03_01_48.pdf"

        expect(subject.location_url).to eq url
      end
    end

    describe "#table_params" do
      it "returns params of table" do
        expected_params =
          {
            "permit_id" => "269757",
            "scan_date" => "7/16/2019",
            "operator_name" => "FASKEN OIL & RANCH LTD [151416]",
            "well_name_full" => "DENTON SWD #003",
            "location" => "M-12-15S-37E",
            "previous_name" => "",
            "new_name" => "",
            "effective_date" => ""
          }

        expect(subject.table_params).to eq expected_params
      end
    end
  end
end
