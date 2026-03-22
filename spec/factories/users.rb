FactoryBot.define do
  factory :user do
    association :organization
    sequence(:name) { |n| "管理者#{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    confirmed_at { Time.current }
    organization_name { organization.name }
  end
end
