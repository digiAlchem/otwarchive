# frozen_string_literal: true

require "spec_helper"

describe AdminMailer do
  describe "#comment_notification" do
    let(:email) { described_class.comment_notification(comment.id) }

    context "when the comment is on an admin post" do
      let(:comment) { create(:comment, :on_admin_post) }

      context "and the comment's contents contain an image" do
        let(:image_url) { "an_image.png" }
        let(:image_tag) { "<img src=\"#{image_url}\" />" }

        before do
          comment.comment_content += image_tag
          comment.save!
        end

        context "when image safety mode is enabled for admin post comments" do
          before { allow(ArchiveConfig).to receive(:PARENTS_WITH_IMAGE_SAFETY_MODE).and_return(["AdminPost"]) }

          it "strips the image from the email message but leaves its URL" do
            expect(email).not_to have_html_part_content(image_tag)
            expect(email).not_to have_text_part_content(image_tag)
            expect(email).to have_html_part_content(image_url)
            expect(email).to have_text_part_content(image_url)
          end
        end

        context "when image safety mode is not enabled for admin post comments" do
          it "embeds the image when image safety mode is completely disabled" do
            allow(ArchiveConfig).to receive(:PARENTS_WITH_IMAGE_SAFETY_MODE).and_return([])
            expect(email).to have_html_part_content(image_tag)
            expect(email).not_to have_text_part_content(image_url)
          end

          it "embeds the image when image safety mode is enabled for other types of comments" do
            allow(ArchiveConfig).to receive(:PARENTS_WITH_IMAGE_SAFETY_MODE).and_return(%w[Chapter Tag])
            expect(email).to have_html_part_content(image_tag)
            expect(email).not_to have_text_part_content(image_url)
          end
        end
      end
    end
  end

  describe "#edited_comment_notification" do
    let(:email) { described_class.edited_comment_notification(comment.id) }

    context "when the comment is on an admin post" do
      let(:comment) { create(:comment, :on_admin_post) }

      context "with an image in the comment content" do
        let(:image_url) { "an_image.png" }
        let(:image_tag) { "<img src=\"#{image_url}\" />" }

        before do
          comment.comment_content += image_tag
          comment.save!
        end

        context "when image safety mode is enabled for admin post comments" do
          before { allow(ArchiveConfig).to receive(:PARENTS_WITH_IMAGE_SAFETY_MODE).and_return(["AdminPost"]) }

          it "strips the image from the email message but leaves its URL" do
            expect(email).not_to have_html_part_content(image_tag)
            expect(email).not_to have_text_part_content(image_tag)
            expect(email).to have_html_part_content(image_url)
            expect(email).to have_text_part_content(image_url)
          end
        end

        context "when image safety mode is not enabled for admin post comments" do
          it "embeds the image in the HTML email when image safety mode is completely disabled" do
            allow(ArchiveConfig).to receive(:PARENTS_WITH_IMAGE_SAFETY_MODE).and_return([])
            expect(email).to have_html_part_content(image_tag)
            expect(email).not_to have_text_part_content(image_url)
          end

          it "embeds the image in the HTML email when image safety mode is enabled for other types of comments" do
            allow(ArchiveConfig).to receive(:PARENTS_WITH_IMAGE_SAFETY_MODE).and_return(%w[Chapter Tag])
            expect(email).to have_html_part_content(image_tag)
            expect(email).not_to have_text_part_content(image_url)
          end
        end
      end
    end
  end

  describe "send_spam_alert" do
    let(:spam_user) { create(:user) }

    let(:spam1) do
      create(:work, spam: true, title: "First Spam",
                    authors: [spam_user.default_pseud])
    end

    let(:spam2) do
      create(:work, spam: true, title: "Second Spam",
                    authors: [spam_user.default_pseud])
    end

    let(:spam3) do
      create(:work, spam: true, title: "Third Spam",
                    authors: [spam_user.default_pseud])
    end

    let(:other_user) { create(:user) }

    let(:other_spam) do
      create(:work, spam: true, title: "Mistaken Spam",
                    authors: [other_user.default_pseud])
    end

    let!(:report) do
      {
        spam_user.id => { "score" => 13, "work_ids" => [spam1.id, spam2.id, spam3.id] },
        other_user.id => { "score" => 5, "work_ids" => [other_spam.id] }
      }
    end

    let(:email) { AdminMailer.send_spam_alert(report) }

    context "when the report is valid" do
      it "has the correct subject" do
        expect(email).to have_subject "[#{ArchiveConfig.APP_SHORT_NAME}] Potential spam alert"
      end

      it "delivers to the correct address" do
        expect(email).to deliver_to ArchiveConfig.SPAM_ALERT_ADDRESS
      end

      it_behaves_like "an email with a valid sender"

      it_behaves_like "a multipart email"

      describe "HTML version" do
        it "lists the usernames and all work titles" do
          expect(email).to have_html_part_content(spam_user.login)
          expect(email).to have_html_part_content(spam1.title)
          expect(email).to have_html_part_content(spam2.title)
          expect(email).to have_html_part_content(spam3.title)

          expect(email).to have_html_part_content(other_user.login)
          expect(email).to have_html_part_content(other_spam.title)
        end

        it "lists the users in the correct order" do
          expect(email.html_part.decoded).to have_text(/#{spam_user.login}.*#{other_user.login}/m)
        end
      end

      describe "text version" do
        it "lists the usernames and all work titles" do
          expect(email).to have_text_part_content(spam_user.login)
          expect(email).to have_text_part_content(spam1.title)
          expect(email).to have_text_part_content(spam2.title)
          expect(email).to have_text_part_content(spam3.title)

          expect(email).to have_text_part_content(other_user.login)
          expect(email).to have_text_part_content(other_spam.title)
        end

        it "lists the users in the correct order" do
          expect(email.text_part.decoded).to have_text(/#{spam_user.login}.*#{other_user.login}/m)
        end
      end
    end

    context "when a user has been deleted" do
      before do
        # Users can't delete their account without doing something with their
        # works first. Here we're orphaning the works:
        create(:user, login: "orphan_account")
        Creatorship.orphan(spam_user.pseuds, spam_user.works, true)
        spam_user.destroy
      end

      context "when there are other users to list" do
        describe "HTML version" do
          it "silently omits the missing user" do
            expect(email).not_to have_html_part_content(spam_user.login)
            expect(email).not_to have_html_part_content(spam1.title)
            expect(email).not_to have_html_part_content(spam2.title)
            expect(email).not_to have_html_part_content(spam3.title)

            expect(email).to have_html_part_content(other_user.login)
            expect(email).to have_html_part_content(other_spam.title)
          end
        end

        describe "text version" do
          it "silently omits the missing user" do
            expect(email).not_to have_text_part_content(spam_user.login)
            expect(email).not_to have_text_part_content(spam1.title)
            expect(email).not_to have_text_part_content(spam2.title)
            expect(email).not_to have_text_part_content(spam3.title)

            expect(email).to have_text_part_content(other_user.login)
            expect(email).to have_text_part_content(other_spam.title)
          end
        end
      end

      context "when there are no other users to list" do
        let!(:report) do
          {
            spam_user.id => { "score" => 13, "work_ids" => [spam1.id, spam2.id, spam3.id] }
          }
        end

        it_behaves_like "an unsent email"
      end
    end
  end

  describe "set_password_notification" do
    subject(:email) { AdminMailer.set_password_notification(admin, token) }

    let(:admin) { create(:admin) }
    let(:token) { "abc123" }

    # Test the headers
    it_behaves_like "an email with a valid sender"

    it "delivers to the correct address" do
      expect(email).to deliver_to(admin.email)
    end

    it "has the correct subject line" do
      subject = "[#{ArchiveConfig.APP_SHORT_NAME}] Your AO3 admin account"
      expect(email).to have_subject(subject)
    end

    # Test both body contents
    it_behaves_like "a multipart email"

    it_behaves_like "a translated email"

    describe "HTML version" do
      it "has the correct content" do
        expect(email).to have_html_part_content("username: </b>#{admin.login}")
        expect(email).to have_html_part_content("URL: </b><a")
        expect(email).to have_html_part_content(">http://www.example.com/admin/login</a>")
        expect(email).to have_html_part_content("</a> so you can log in.")
        expect(email).to have_html_part_content(token)
      end
    end

    describe "text version" do
      it "has the correct content" do
        expect(email).to have_text_part_content("Admin username: #{admin.login}")
        expect(email).to have_text_part_content("Admin login URL: http://www.example.com/admin/login")
        expect(email).to have_text_part_content("so you can log in:")
        expect(email).to have_text_part_content(token)
      end
    end
  end
end
