import DesignSystem
import Env
import Introspect
import Models
import Network
import Shimmer
import Status
import SwiftUI

public struct TimelineView: View {
  private enum Constants {
    static let scrollToTop = "top"
  }

  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var theme: Theme
  @EnvironmentObject private var account: CurrentAccount
  @EnvironmentObject private var preferences: UserPreferences
  @EnvironmentObject private var watcher: StreamWatcher
  @EnvironmentObject private var client: Client
  @EnvironmentObject private var routerPath: RouterPath
  @EnvironmentObject private var maskingVisible: MaskingVisible

  @StateObject private var viewModel = TimelineViewModel()
  @StateObject private var prefetcher = TimelinePrefetcher()

  @State private var wasBackgrounded: Bool = false
  @State private var collectionView: UICollectionView?

  @Binding var timeline: TimelineFilter
  @Binding var scrollToTopSignal: Int
  private let canFilterTimeline: Bool
  
  private let toolbarTitleIcon = Image(systemName: "chevron.down.circle")

  public init(timeline: Binding<TimelineFilter>, scrollToTopSignal: Binding<Int>, canFilterTimeline: Bool) {
    _timeline = timeline
    _scrollToTopSignal = scrollToTopSignal
    self.canFilterTimeline = canFilterTimeline
  }

  public var body: some View {
    ScrollViewReader { proxy in
      ZStack(alignment: .top) {
        List {
          if viewModel.tag == nil {
            scrollToTopView
          } else {
            tagHeaderView
          }
          switch viewModel.timeline {
          case .remoteLocal:
            StatusesListView(fetcher: viewModel, client: client, routerPath: routerPath, isRemote: true)
          default:
            StatusesListView(fetcher: viewModel, client: client, routerPath: routerPath)
          }
        }
        .id(client.id)
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.primaryBackgroundColor)
        .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining) { (collectionView: UICollectionView) in
          self.collectionView = collectionView
          self.prefetcher.viewModel = viewModel
          collectionView.isPrefetchingEnabled = true
          collectionView.prefetchDataSource = self.prefetcher
        }
        if viewModel.timeline.supportNewestPagination {
          PendingStatusesObserverView(observer: viewModel.pendingStatusesObserver)
        }
      }
      .onChange(of: viewModel.scrollToIndex) { index in
        if let collectionView,
           let index,
           let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
           rows > index
        {
          collectionView.scrollToItem(at: .init(row: index, section: 0),
                                      at: .top,
                                      animated: viewModel.scrollToIndexAnimated)
          viewModel.scrollToIndexAnimated = false
          viewModel.scrollToIndex = nil
        }
      }
      .onChange(of: scrollToTopSignal, perform: { _ in
        withAnimation {
          proxy.scrollTo(Constants.scrollToTop, anchor: .top)
        }
      })
    }
    .toolbar {
      toolbarTitleView
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.isTimelineVisible = true

      if viewModel.client == nil {
        viewModel.client = client
      }

      viewModel.timeline = timeline
    }
    .onDisappear {
      viewModel.isTimelineVisible = false
    }
    .refreshable {
      SoundEffectManager.shared.playSound(of: .pull)
      HapticManager.shared.fireHaptic(of: .dataRefresh(intensity: 0.3))
      await viewModel.pullToRefresh()
      HapticManager.shared.fireHaptic(of: .dataRefresh(intensity: 0.7))
      SoundEffectManager.shared.playSound(of: .refresh)
    }
    .onChange(of: watcher.latestEvent?.id) { _ in
      if let latestEvent = watcher.latestEvent {
        viewModel.handleEvent(event: latestEvent, currentAccount: account)
      }
    }
    .onChange(of: timeline) { newTimeline in
      switch newTimeline {
      case let .remoteLocal(server, _):
        viewModel.client = Client(server: server)
      default:
        viewModel.client = client
      }
      viewModel.timeline = newTimeline
    }
    .onChange(of: viewModel.timeline, perform: { newValue in
      timeline = newValue
    })
    .onChange(of: scenePhase, perform: { scenePhase in
      switch scenePhase {
      case .active:
        if wasBackgrounded {
          wasBackgrounded = false
          viewModel.refreshTimeline()
        }
      case .background:
        wasBackgrounded = true

      default:
        break
      }
    })
  }
  
  @ToolbarContentBuilder
  private var toolbarTitleView: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Menu {
        if canFilterTimeline {
          timelineFilterButton
        }
      } label: {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
          VStack(alignment: .center) {
            switch timeline {
            case let .remoteLocal(_, filter):
              Text(filter.localizedTitle())
                .font(.headline)
              Text(timeline.localizedTitle())
                .font(.caption)
                .foregroundColor(.gray)
            default:
              Text(timeline.localizedTitle())
                .font(.headline)
            }
          }
          .aspectRatio(contentMode: .fit)
          .foregroundColor(.black)
          .alignmentGuide(HorizontalAlignment.center, computeValue: { d in
            d[HorizontalAlignment.center] + d.width / 2 + 2.5
          })
          .accessibilityRepresentation {
            switch timeline {
            case let .remoteLocal(_, filter):
              if canFilterTimeline {
                Menu(filter.localizedTitle()) {}
              } else {
                Text(filter.localizedTitle())
              }
            default:
              if canFilterTimeline {
                Menu(timeline.localizedTitle()) {}
              } else {
                Text(timeline.localizedTitle())
              }

            }
          }
          .accessibilityAddTraits(.isHeader)
          .accessibilityRemoveTraits(.isButton)
          .accessibilityRespondsToUserInteraction(canFilterTimeline)

          toolbarTitleIcon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 15, height: 15)
            .foregroundColor(Color.gray.opacity(0.7))
            .alignmentGuide(HorizontalAlignment.center) { d in
              return d[HorizontalAlignment.center] - d.width / 2 - 2.5
            }
        }
      }
      .onTapGesture {
        maskingVisible.toggle()
      }
    }
  }
  
  @ViewBuilder
  private var timelineFilterButton: some View {
    ZStack {
      if timeline.supportNewestPagination {
        Button {
          maskingVisible.toggle()
          self.timeline = .latest
        } label: {
          Label(TimelineFilter.latest.localizedTitle(), systemImage: TimelineFilter.latest.iconName() ?? "")
        }
        .keyboardShortcut("r", modifiers: .command)
        Divider()
      }
      ForEach(TimelineFilter.availableTimeline(client: client), id: \.self) { timeline in
        Button {
          maskingVisible.toggle()
          self.timeline = timeline
        } label: {
          Label(timeline.localizedTitle(), systemImage: timeline.iconName() ?? "")
        }
      }
      if !account.lists.isEmpty {
        Menu("timeline.filter.lists") {
          ForEach(account.sortedLists) { list in
            Button {
              maskingVisible.toggle()
              timeline = .list(list: list)
            } label: {
              Label(list.title, systemImage: "list.bullet")
            }
          }
        }
      }
      
      if !account.tags.isEmpty {
        Menu("timeline.filter.tags") {
          ForEach(account.sortedTags) { tag in
            Button {
              maskingVisible.toggle()
              timeline = .hashtag(tag: tag.name, accountId: nil)
            } label: {
              Label("#\(tag.name)", systemImage: "number")
            }
          }
        }
      }
      
      Menu("timeline.filter.local") {
        ForEach(preferences.remoteLocalTimelines, id: \.self) { server in
          Button {
            maskingVisible.toggle()
            timeline = .remoteLocal(server: server, filter: .local)
          } label: {
            VStack {
              Label(server, systemImage: "dot.radiowaves.right")
            }
          }
        }
        Button {
          maskingVisible.toggle()
          routerPath.presentedSheet = .addRemoteLocalTimeline
        } label: {
          Label("timeline.filter.add-local", systemImage: "badge.plus.radiowaves.right")
        }
      }
    }
  }

  @ViewBuilder
  private var tagHeaderView: some View {
    if let tag = viewModel.tag {
      VStack(alignment: .leading) {
        Spacer()
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("#\(tag.name)")
              .font(.scaledHeadline)
            Text("timeline.n-recent-from-n-participants \(tag.totalUses) \(tag.totalAccounts)")
              .font(.scaledFootnote)
              .foregroundColor(.gray)
          }
          .accessibilityElement(children: .combine)
          Spacer()
          Button {
            Task {
              if tag.following {
                viewModel.tag = await account.unfollowTag(id: tag.name)
              } else {
                viewModel.tag = await account.followTag(id: tag.name)
              }
            }
          } label: {
            Text(tag.following ? "account.follow.following" : "account.follow.follow")
          }.buttonStyle(.bordered)
        }
        Spacer()
      }
      .listRowBackground(theme.secondaryBackgroundColor)
      .listRowSeparator(.hidden)
      .listRowInsets(.init(top: 8,
                           leading: .layoutPadding,
                           bottom: 8,
                           trailing: .layoutPadding))
    }
  }

  private var scrollToTopView: some View {
    HStack { EmptyView() }
      .listRowBackground(theme.primaryBackgroundColor)
      .listRowSeparator(.hidden)
      .listRowInsets(.init())
      .frame(height: .layoutPadding)
      .id(Constants.scrollToTop)
      .onAppear {
        viewModel.scrollToTopVisible = true
      }
      .onDisappear {
        viewModel.scrollToTopVisible = false
      }
      .accessibilityHidden(true)
  }
}
