require "rails_helper"

RSpec.describe "Staffs", type: :request do
  describe "GET /staffs" do
    it "未ログインならログイン画面へリダイレクト" do
      get staffs_path

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "ログイン済みなら職員一覧画面を表示できる" do
      user = create(:user)
      sign_in user

      get staffs_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /staffs / 職員登録" do
    it "正常な値なら職員を登録できる" do
      user = create(:user)
      sign_in user
      occupation = create(:occupation, name: "看護師")

      expect do
        post staffs_path, params: {
          staff: {
            occupation_id: occupation.id,
            last_name: "山田",
            first_name: "花子",
            last_name_kana: "やまだ",
            first_name_kana: "はなこ",
            can_day: "1",
            can_early: "0",
            can_late: "0",
            can_night: "0",
            can_visit: "0",
            can_drive: "0",
            can_cook: "0",
            workday_constraint: "free",
            assignment_policy: "candidate",
            weekly_workdays: "",
            workable_wdays: [],
            unworkable_wdays: []
          }
        }
      end.to change(user.staffs, :count).by(1)

      expect(response).to redirect_to(staffs_path)
    end

    it "不正な値なら職員を登録できない" do
      user = create(:user)
      sign_in user
      occupation = create(:occupation, name: "看護師")

      expect do
        post staffs_path, params: {
          staff: {
            occupation_id: occupation.id,
            last_name: "",
            first_name: "花子",
            last_name_kana: "やまだ",
            first_name_kana: "はなこ",
            can_day: "1",
            can_early: "0",
            can_late: "0",
            can_night: "0",
            can_visit: "0",
            can_drive: "0",
            can_cook: "0",
            workday_constraint: "free",
            assignment_policy: "candidate",
            weekly_workdays: "",
            workable_wdays: [],
            unworkable_wdays: []
          }
        }
      end.not_to change(user.staffs, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "security / IDOR対策" do
    it "他ユーザーのstaffにはアクセスできない" do
      user1 = create(:user)
      user2 = create(:user)

      occupation = create(:occupation)

      staff = create(:staff, user: user1, occupation: occupation)

      sign_in user2

      get edit_staff_path(staff)
      expect(response).to have_http_status(:not_found)
    end

    it "他ユーザーのstaffは更新できない" do
      user1 = create(:user)
      user2 = create(:user)

      occupation = create(:occupation)
      staff = create(:staff, user: user1, occupation: occupation, last_name: "山田")

      sign_in user2

      patch staff_path(staff), params: {
        staff: {
          occupation_id: occupation.id,
          last_name: "佐藤",
          first_name: staff.first_name,
          last_name_kana: staff.last_name_kana,
          first_name_kana: staff.first_name_kana,
          can_day: "1",
          can_early: "0",
          can_late: "0",
          can_night: "0",
          can_visit: "0",
          can_drive: "0",
          can_cook: "0",
          workday_constraint: "free",
          assignment_policy: "candidate",
          weekly_workdays: "",
          workable_wdays: [],
          unworkable_wdays: []
        }
      }

      expect(response).to have_http_status(:not_found)
      expect(staff.reload.last_name).to eq("山田")
    end

    it "他ユーザーのstaffは削除できない" do
      user1 = create(:user)
      user2 = create(:user)

      staff = create(:staff, user: user1)

      sign_in user2

      expect {
        delete staff_path(staff)
      }.not_to change(Staff, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /staffs/:id / 職員更新" do
    it "自分のstaffを正常な値で更新できる" do
      user = create(:user)
      sign_in user

      occupation = create(:occupation, name: "看護師")
      staff = create(:staff, user: user, occupation: occupation, last_name: "山田")

      patch staff_path(staff), params: {
        staff: {
          occupation_id: occupation.id,
          last_name: "佐藤",
          first_name: staff.first_name,
          last_name_kana: staff.last_name_kana,
          first_name_kana: staff.first_name_kana,
          can_day: "1",
          can_early: "0",
          can_late: "0",
          can_night: "0",
          can_visit: "0",
          can_drive: "0",
          can_cook: "0",
          workday_constraint: "free",
          assignment_policy: "candidate",
          weekly_workdays: "",
          workable_wdays: [],
          unworkable_wdays: []
        }
      }

      expect(response).to redirect_to(staffs_path)
      expect(staff.reload.last_name).to eq("佐藤")
    end

    it "不正な値なら更新できない" do
      user = create(:user)
      sign_in user

      occupation = create(:occupation)
      staff = create(:staff, user: user, occupation: occupation, last_name: "山田")

      patch staff_path(staff), params: {
        staff: {
          occupation_id: occupation.id,
          last_name: "", # ← invalid
          first_name: staff.first_name,
          last_name_kana: staff.last_name_kana,
          first_name_kana: staff.first_name_kana,
          can_day: "1",
          can_early: "0",
          can_late: "0",
          can_night: "0",
          can_visit: "0",
          can_drive: "0",
          can_cook: "0",
          workday_constraint: "free",
          assignment_policy: "candidate",
          weekly_workdays: "",
          workable_wdays: [],
          unworkable_wdays: []
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(staff.reload.last_name).to eq("山田")
    end
  end

  describe "DELETE /staffs/:id / 職員削除" do
    it "シフト使用がなければ物理削除する" do
      user = create(:user)
      sign_in user

      staff = create(:staff, user: user)

      expect do
        delete staff_path(staff)
      end.to change(Staff, :count).by(-1)

      expect(response).to redirect_to(staffs_path)
    end

    it "シフト使用があれば無効化する" do
      user = create(:user)
      sign_in user

      staff = create(:staff, user: user)
      shift_month = user.shift_months.create!(
        year: 2026,
        month: 3,
        organization: user.organization
      )
      ShiftDayAssignment.create!(
        shift_month: shift_month,
        staff: staff,
        date: Date.new(2026, 3, 1),
        shift_kind: :day,
        source: :confirmed,
        slot: 0
      )

      expect do
        delete staff_path(staff)
      end.not_to change(Staff, :count)

      expect(response).to redirect_to(staffs_path)
      expect(staff.reload.active).to eq(false)
    end
  end
end
