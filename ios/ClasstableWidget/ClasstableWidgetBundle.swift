// Copyright 2023-2025 BenderBlog Rodriguez and contributors
// Copyright 2025 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0
//
//  ClasstableWidgetBundle.swift
//  ClasstableWidget
//
//  Created by BenderBlog Rodriguez on 2024/1/7.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ClasstableWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClasstableWidget()

        /// The class which is going on, shown in the Dynamic Island and on the
        /// lock screen.
        if #available(iOSApplicationExtension 16.2, *) {
            CourseLiveActivityWidget()
        }
    }
}

/// The state of the class which is going on.
///
/// The very same declaration is compiled into the app as well, ActivityKit
/// matches the two by name.
@available(iOSApplicationExtension 16.2, *)
struct CourseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var name: String
        /// A very short form of the name, for the collapsed island.
        var shortTitle: String
        /// The classroom and the teacher.
        var location: String
        /// "第 3-4 节"
        var periodText: String
        /// "08:30 - 10:05"
        var timeText: String
        /// "下一节 10:25 · B-106"
        var nextText: String
        /// "即将开始", shown while the class has not begun yet.
        var upcomingText: String
        /// How many class periods the lesson takes.
        var periods: Int
        var startDate: Date
        var endDate: Date
        /// The colour of the course card, in the `#RRGGBB` form.
        var colorHex: String
    }

    var courseId: String
}

@available(iOSApplicationExtension 16.2, *)
struct CourseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            CourseActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.name).lineLimit(1)
                            if !context.state.periodText.isEmpty {
                                Text(context.state.periodText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        CourseActivityBadge(state: context.state)
                    }
                    .font(.caption)
                    .foregroundStyle(CourseActivityColor.of(context.state.colorHex))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    CourseActivityCountdown(state: context.state)
                        .font(.caption)
                        .monospacedDigit()
                        .frame(maxWidth: 64)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    CourseActivityProgress(state: context.state)
                }
            } compactLeading: {
                CourseActivityBadge(state: context.state)
            } compactTrailing: {
                CourseActivityCountdown(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                CourseActivityBadge(
                    state: context.state,
                    singleCharacter: true
                )
            }
            .keylineTint(CourseActivityColor.of(context.state.colorHex))
        }
    }
}

/// The short name of the course on its own colour.
///
/// The collapsed island has room for a couple of characters only; showing the
/// name there tells more than the icon of the app would.
@available(iOSApplicationExtension 16.2, *)
private struct CourseActivityBadge: View {
    let state: CourseActivityAttributes.ContentState
    var singleCharacter: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                CourseActivityColor.of(state.colorHex),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private var label: String {
        let name = state.shortTitle.isEmpty ? state.name : state.shortTitle
        return singleCharacter ? String(name.prefix(1)) : String(name.prefix(2))
    }
}

/// The countdown shown inside the island: it runs towards the beginning of the
/// class, and towards its end once the class has started. The system keeps it
/// up to date on its own.
@available(iOSApplicationExtension 16.2, *)
private struct CourseActivityCountdown: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        if Date() < state.startDate {
            Text(timerInterval: Date()...state.startDate, countsDown: true)
        } else {
            Text(timerInterval: Date()...state.endDate, countsDown: true)
        }
    }
}

/// The progress of the class, from its start to its end. It is animated by the
/// system as well.
@available(iOSApplicationExtension 16.2, *)
private struct CourseActivityProgress: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(state.timeText.isEmpty ? timeRange : state.timeText)
                    .font(.caption2)
                    .monospacedDigit()

                Spacer(minLength: 4)

                if !state.location.isEmpty {
                    Text(state.location)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)

            ProgressView(
                timerInterval: state.startDate...state.endDate,
                countsDown: false
            )
            .tint(CourseActivityColor.of(state.colorHex))

            if !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The line under the bar.
    ///
    /// Before the class begins the countdown runs towards its start, which looks
    /// exactly like the countdown to the end of a class, so the hint that it has
    /// not begun yet comes first - the same line the Android side shows. Once it
    /// has begun the class which comes next is worth more than the clock.
    private var footnote: String {
        if Date() < state.startDate {
            return [state.upcomingText, state.timeText]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        return state.nextText.isEmpty ? state.timeText : state.nextText
    }

    private var timeRange: String {
        "\(CourseActivityColor.time(state.startDate)) - \(CourseActivityColor.time(state.endDate))"
    }
}

/// The same information, laid out for the lock screen.
@available(iOSApplicationExtension 16.2, *)
private struct CourseActivityLockScreenView: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundStyle(CourseActivityColor.of(context.state.colorHex))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.name)
                    .font(.headline)
                    .lineLimit(1)

                CourseActivityProgress(state: context.state)
            }

            Spacer(minLength: 8)

            CourseActivityCountdown(state: context.state)
                .font(.callout)
                .monospacedDigit()
        }
        .padding()
        .foregroundStyle(.white)
    }
}

@available(iOSApplicationExtension 16.2, *)
enum CourseActivityColor {
    /// Turns the `#RRGGBB` (or `#AARRGGBB`) string of the app into a colour.
    static func of(_ hex: String) -> Color {
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 6 {
            value = "FF" + value
        }
        guard value.count == 8, let raw = UInt64(value, radix: 16) else {
            return .accentColor
        }

        return Color(
            .sRGB,
            red: Double((raw >> 16) & 0xFF) / 255.0,
            green: Double((raw >> 8) & 0xFF) / 255.0,
            blue: Double(raw & 0xFF) / 255.0,
            opacity: Double((raw >> 24) & 0xFF) / 255.0
        )
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
