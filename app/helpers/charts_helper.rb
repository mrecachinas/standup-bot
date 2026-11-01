module ChartsHelper
  CHART_WIDTH = 720
  RUN_SEGMENTS = %i[completed skipped pending missed].freeze

  # Stacked columns, one per standup run: completed / skipped / pending / missed.
  def run_breakdown_chart(runs, height: 200, width: CHART_WIDTH, label: "Responses per run")
    return chart_empty("No standup runs in this period yet.") if runs.blank?

    left = 32
    bottom = 22
    top = 8
    plot_width = width - left
    plot_height = height - bottom - top
    max = nice_max(runs.map { |run| RUN_SEGMENTS.sum { |key| run[key].to_i } }.max)
    band = plot_width.to_f / runs.size
    bar_width = [ band * 0.62, 28 ].min
    label_every = (runs.size / 10.0).ceil.clamp(1, 100)

    content = y_axis(max, left:, top:, plot_height:, width:)
    runs.each_with_index do |run, index|
      x = left + (band * index) + ((band - bar_width) / 2)
      y = top + plot_height
      segments = RUN_SEGMENTS.filter_map do |key|
        value = run[key].to_i
        next if value.zero?

        segment_height = (value.to_f / max) * plot_height
        y -= segment_height
        tag.rect(x: x.round(2), y: y.round(2), width: bar_width.round(2), height: segment_height.round(2), class: "bar-#{key}")
      end
      summary = "#{run[:date].strftime("%b %-d, %Y")}: #{run[:completed]} completed, #{run[:skipped]} skipped, #{run[:missed]} missed" \
        "#{", #{run[:pending]} pending" if run[:pending].to_i.positive?} (#{run[:completion_rate].round}%)"
      content << tag.g(tag.title(summary) + safe_join(segments) +
        tag.rect(x: (left + band * index).round(2), y: top, width: band.round(2), height: plot_height, fill: "transparent"), class: "bar-group")
      if (index % label_every).zero?
        content << tag.text(run[:date].strftime("%b %-d"), x: (x + bar_width / 2).round(2), y: height - 6, "text-anchor": "middle")
      end
    end

    svg_chart(content, height:, width:, label:)
  end

  # Line + area for a percentage series (0–100).
  def rate_line_chart(points, height: 200, width: CHART_WIDTH, label: "Completion rate")
    return chart_empty("Not enough data to chart yet.") if points.blank?

    left = 36
    bottom = 22
    top = 10
    right = 8
    plot_width = width - left - right
    plot_height = height - bottom - top
    step = points.size > 1 ? plot_width.to_f / (points.size - 1) : 0
    coords = points.each_with_index.map do |point, index|
      x = points.size > 1 ? left + step * index : left + plot_width / 2.0
      y = top + plot_height - (point[:value].to_f.clamp(0, 100) / 100.0 * plot_height)
      [ x.round(2), y.round(2) ]
    end
    label_every = (points.size / 8.0).ceil.clamp(1, 100)

    content = tag.defs(tag.linearGradient(
      tag.stop(offset: "0%", "stop-color": "#4f46e5", "stop-opacity": "0.18") +
      tag.stop(offset: "100%", "stop-color": "#4f46e5", "stop-opacity": "0"),
      id: "area-gradient", x1: 0, y1: 0, x2: 0, y2: 1))
    content << y_axis(100, left:, top:, plot_height:, width:, suffix: "%", right:)
    baseline = top + plot_height
    area = "M#{coords.first[0]},#{baseline} " + coords.map { |x, y| "L#{x},#{y}" }.join(" ") + " L#{coords.last[0]},#{baseline} Z"
    content << tag.path(d: area, class: "area")
    content << tag.polyline(points: coords.map { |x, y| "#{x},#{y}" }.join(" "), class: "line")
    points.each_with_index do |point, index|
      x, y = coords[index]
      content << tag.circle(tag.title(point[:title] || "#{point[:label]}: #{point[:value].round}%"), cx: x, cy: y, r: 3, class: "point")
      if (index % label_every).zero? || index == points.size - 1
        content << tag.text(point[:label], x: x, y: height - 6, "text-anchor": "middle")
      end
    end

    svg_chart(content, height:, width:, label:)
  end

  def sparkline(values, width: 96, height: 28)
    values = Array(values).compact
    return tag.span("—", class: "subtle") if values.size < 2

    step = width.to_f / (values.size - 1)
    coords = values.each_with_index.map do |value, index|
      [ (step * index).round(2), (height - 2 - (value.to_f.clamp(0, 100) / 100.0 * (height - 4))).round(2) ]
    end
    line = coords.map { |x, y| "#{x},#{y}" }.join(" ")
    area = "M0,#{height} " + coords.map { |x, y| "L#{x},#{y}" }.join(" ") + " L#{width},#{height} Z"
    tag.svg(tag.path(d: area, class: "area") + tag.polyline(points: line, class: "line"),
      class: "sparkline", width: width, height: height, viewBox: "0 0 #{width} #{height}",
      role: "img", "aria-label": "Completion trend: #{values.map { |value| "#{value.round}%" }.join(', ')}")
  end

  def run_legend(pending: false)
    items = [ [ "completed", "Completed" ], [ "skipped", "Skipped" ] ]
    items << [ "pending", "Pending" ] if pending
    items << [ "missed", "Missed" ]
    tag.div(class: "legend") do
      safe_join(items.map { |key, text| tag.span(tag.i(class: "swatch-#{key}") + text) })
    end
  end

  private

  def svg_chart(content, height:, width:, label:)
    tag.svg(content, class: "chart", viewBox: "0 0 #{width} #{height}",
      role: "img", "aria-label": label)
  end

  def y_axis(max, left:, top:, plot_height:, width:, suffix: "", right: 0)
    ticks = [ 0, max / 2.0, max ]
    safe_join(ticks.map do |tick|
      y = (top + plot_height - (tick.to_f / max * plot_height)).round(2)
      css = tick.zero? ? "axis-line" : "grid-line"
      tag.line(x1: left, x2: width - right, y1: y, y2: y, class: css) +
        tag.text("#{tick.round}#{suffix}", x: left - 8, y: y + 3.5, "text-anchor": "end")
    end)
  end

  def nice_max(value)
    value = value.to_i
    return 2 if value <= 2

    magnitude = 10**Math.log10(value).floor
    [ 1, 2, 2.5, 5, 10 ].map { |factor| (factor * magnitude).ceil }.find { |candidate| candidate >= value && candidate.even? } || value + (value % 2)
  end

  def chart_empty(message)
    tag.div(message, class: "chart-empty")
  end
end
