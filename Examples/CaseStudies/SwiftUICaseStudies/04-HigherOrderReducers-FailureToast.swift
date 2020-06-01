import Combine
import ComposableArchitecture
import SwiftUI

private let readMe = """
  This screen demonstrates how the `Reducer` struct can be extended to enhance reducers with extra \
  functionality.

  In it we introduce an `errorHandling` reducer that consumes the failable `appReducer`. \
  It handles the errors by way of a toast, and returns the usual non-failing reducer.

  This form of reducer is useful if you want to centralize and handle failures in the same way. \
  Without this, each routine executed in the `appReducer` would need to handle it's own failure.

  Tapping the "Load Data" button will fail after one second and show a toast.
  """

// MARK: - Failure Toast Domain

struct ToastState: Equatable {
  var status: ToastStatus = .hiding
}

enum ToastStatus: Equatable {
  case showing(String)
  case hiding

  var isShowing: Bool {
      switch self {
      case .showing: return true
      case .hiding: return false
      }
  }

  var text: String {
      switch self {
      case .showing(let text): return text
      case .hiding: return ""
      }
  }
}

enum ToastAction {
  case show(String)
  case hide
}

let toastReducer = Reducer<ToastState, ToastAction, Void> { state, action, _ in
  switch action {
  case .show(let text):
    state.status = .showing(text)
    return .none

  case .hide:
    state.status = .hiding
    return .none
  }
}

extension Reducer {
  // The higher order reducer
  static func errorHandling(
    _ reducer: @escaping (inout AppState, AppAction, AppEnvironment) -> Effect<AppAction, Error>
  ) -> Reducer<AppState, AppAction, AppEnvironment> {
    Reducer<AppState, AppAction, AppEnvironment> { state, action, environment in
      reducer(&state, action, environment)
        .catch { Just(.toastAction(.show($0.localizedDescription))) }
        .eraseToEffect()
    }
  }
}

struct ToastView: View {
  let store: Store<ToastState, ToastAction>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      if viewStore.status.isShowing {
        Text(viewStore.status.text)
          .padding()
          .foregroundColor(.white)
          .background(Color.gray.opacity(0.8))
          .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { viewStore.send(.hide) }
          }
      }
    }
  }
}

// MARK - Feature Domain

enum AppError: Error, LocalizedError {
  case api

  var errorDescription: String? { "Whoops! There was a server error." }
}

struct AppState: Equatable {
  var profileState = ProfileState()
  var toastState = ToastState()
  var data: [String] = []
}

enum AppAction {
  case profileAction(ProfileAction)
  case toastAction(ToastAction)
  case loadData
  case didLoadData([String])
}

struct AppEnvironment {
  var loadData: () -> Effect<[String], Error>
}

let appReducer = FailableReducer<AppState, AppAction, AppEnvironment> { state, action, environment in
  switch action {
  case .toastAction:
    return .none

  case .loadData:
    return environment.loadData().map(AppAction.didLoadData)

  case .didLoadData(let data):
    state.data = data
    return .none

  case .profileAction(_):
    return .none
  }
}

struct AppView: View {
  let store: Store<AppState, AppAction>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      ZStack(alignment: .bottom) {
        Form {
          Section(header: Text(template: readMe, .caption)) {
            Button("Load Data") { viewStore.send(.loadData) }
            ForEach(viewStore.state.data, id: \.self) { Text($0) }
          }
          Section(header: Text(template: readMe, .caption)) {
            ProfileView(
              store: self.store.scope(
                state: { $0.profileState },
                action: { AppAction.profileAction($0) }
              )
            )
          }
        }
        ToastView(
          store: self.store.scope(
            state: { $0.toastState },
            action: AppAction.toastAction
          )
        )
      }
      .navigationBarTitle("Failure Toast")
    }
  }
}

struct ProfileView: View {
  let store: Store<ProfileState, ProfileAction>
  var body: some View {
    WithViewStore(self.store) { viewStore in
      Button("Load Profile") { viewStore.send(.loadProfile) }
    }
  }
}


struct FailableReducer<State, Action, Environment> {
  let reducer: (inout State, Action, Environment) -> Effect<Action, Error>

  public static func combine(_ reducers: [FailableReducer]) -> FailableReducer {
    Self { value, action, environment in
      .merge(reducers.map { $0.reducer(&value, action, environment) })
    }
  }

  func pullback<GlobalState, GlobalAction, GlobalEnvironment>(
    state toLocalState: WritableKeyPath<GlobalState, State>,
    action toLocalAction: CasePath<GlobalAction, Action>,
    environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment
  ) -> FailableReducer<GlobalState, GlobalAction, GlobalEnvironment> {
    .init { globalState, globalAction, globalEnvironment in
      guard let localAction = toLocalAction.extract(from: globalAction) else { return .none }
      return self.reducer(
        &globalState[keyPath: toLocalState],
        localAction,
        toLocalEnvironment(globalEnvironment)
      )
        .map(toLocalAction.embed)
    }
  }
}

struct ProfileState: Equatable {}

enum ProfileAction {
  case loadProfile
  case didLoadProfile(String)
}

struct ProfileEnvironment {
  func loadProfile() -> AnyPublisher<String, Error> {
    Fail(error: AppError.api).eraseToAnyPublisher()
  }
}

let profileReducer = FailableReducer<ProfileState, ProfileAction, ProfileEnvironment> { state, result, environment in
  switch result {
  case .loadProfile:
    return environment
      .loadProfile()
      .map { .didLoadProfile($0) }
      .eraseToEffect()

  case .didLoadProfile(_):
    break
  }
  return .none
}

let appAndProfileReducer = FailableReducer<AppState, AppAction, AppEnvironment>.combine([
  appReducer,
  profileReducer.pullback(
    state: \.profileState,
    action: /AppAction.profileAction,
    environment: { _ in ProfileEnvironment() }
  )
])

let combinedFailureToastReducer = Reducer<AppState, AppAction, AppEnvironment>.combine(
  .errorHandling(
    appAndProfileReducer.reducer
  ),
  toastReducer.pullback(
    state: \AppState.toastState,
    action: /AppAction.toastAction,
    environment: { _ in () }
  )
)

struct ToastView_Previews: PreviewProvider {
  static var previews: some View {
    AppView(
      store: Store(
        initialState: AppState(),
        reducer: combinedFailureToastReducer,
        environment: AppEnvironment(
          loadData: {
            Fail(error: AppError.api)
              .delay(for: 1, scheduler: DispatchQueue.main)
              .eraseToEffect()
          }
        )
      )
    )
  }
}
