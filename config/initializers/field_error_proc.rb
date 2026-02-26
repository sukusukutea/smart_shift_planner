# バリデーションエラー時に Rails が <div class="field_with_errors"> でラップして
# input-group / flex のレイアウトが崩れるのを防ぐ
ActionView::Base.field_error_proc = proc do |html_tag, _instance|
  # 余計なラップをせず、そのまま返す（レイアウト崩れ防止）
  html_tag.html_safe
end
