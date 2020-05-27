import Combine
import ComposableArchitecture
import SwiftUI

private let readMe = """
  fixme
  """

extension Publisher {
  public func fireAndForget() -> Effect<Output, Failure> {
    flatMap { _ in Effect<Output, Failure>.none }
      .catch { _ in Effect<Output, Failure>.none }
      .eraseToEffect()
  }
}

enum AppError: Error {
  case api
}

enum APIError: Error {
  case unauthorized
}

struct AppState: Equatable {
  var toastStatus: ToastStatus = .hiding
  var name: String = ""
  var token: String?
  var isLoading: Bool = false
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

enum AppAction {
  case showToast(String)
  case hideToast
//  case startSaveName
  case saveName(String)
  case didSaveName(String)
  case logout
  case handleUnauthorized
  case showLoading
  case hideLoading
}

struct AppEnvironment {
  var mainQueue: AnySchedulerOf<DispatchQueue> = DispatchQueue.main.eraseToAnyScheduler()
  var saveName: (String) -> AnyPublisher<Void, Error> = { name in
//    Result<Void, Error>.success(()).publisher.delay(for: 2.0, scheduler: DispatchQueue.main).eraseToAnyPublisher()
    Fail(error: AppError.api).delay(for: 2.0, scheduler: DispatchQueue.main).eraseToAnyPublisher()
  }
  var logout: () -> AnyPublisher<Void, Never> = { Just(()).eraseToAnyPublisher() }
  var delay: () -> AnyPublisher<Void, Never> = { Just(()).delay(for: 2.0, scheduler: DispatchQueue.main).eraseToAnyPublisher() }
}

let appReducer: (inout AppState, AppAction, AppEnvironment) -> Effect<AppAction, Error> = { state, action, environment in
  switch action {
  case .showToast(let text):
    state.toastStatus = .showing(text)
    return .none

  case .hideToast:
    state.toastStatus = .hiding
    return .none

//  case .startSaveName(let name):
//    return [
//        AppAction.showLoading,
//        AppAction.saveName(name)
//        ]
//        .publisher
//        .mapError { $0 as Error }
//        .eraseToEffect()

  case .saveName(let name):
    print("saveName")
    let showLoaderEffect = Effect<AppAction, Error>(value: .showLoading)
    let didSaveNameEffect = environment.saveName(name)
      .map { AppAction.didSaveName(name) }
      .eraseToEffect()
    let hideLoaderEffect = Effect<AppAction, Error>(value: .hideLoading)

    return Effect.concatenate(showLoaderEffect, didSaveNameEffect, hideLoaderEffect)

  case .didSaveName(let name):
    print("didSaveName")
    state.name = name
    return .none

  case .logout:
    state.token = nil
    return environment.logout()
        .mapError { $0 as Error }
        .flatMap { Effect<AppAction, Error>.none }
        .eraseToEffect()

  case .handleUnauthorized:
    return [
        AppAction.logout,
        AppAction.showToast("Session expired")
        ]
        .publisher
        .mapError { $0 as Error }
        .eraseToEffect()

  case .showLoading:
    state.isLoading = true
    print("showLoading")
    return .none

  case .hideLoading:
    state.isLoading = false
    print("hideLoading")
    return .none

    }
}

extension Reducer {
  static func errorHandling(
    _ reducer: @escaping (inout AppState, AppAction, AppEnvironment) -> Effect<AppAction, Error>
  ) -> Reducer<AppState, AppAction, AppEnvironment> {
    Reducer<AppState, AppAction, AppEnvironment>.combine(
      Reducer<AppState, AppAction, AppEnvironment> { state, action, environment in
        reducer(&state, action, environment)
          .catch { error -> Effect<AppAction, Never> in
            if case APIError.unauthorized = error {
              return Just(AppAction.handleUnauthorized)
                .flatMap { Effect.concatenate(Effect(value: $0), Effect(value: AppAction.hideLoading) ) }
                .eraseToEffect()
            }

            return Just(AppAction.showToast(error.localizedDescription))
              .flatMap { Effect.concatenate(Effect(value: $0), Effect(value: AppAction.hideLoading) ) }
              .eraseToEffect()
          }
          //        .append(AppAction.hideLoading)
          .eraseToEffect()
      }
//      ,
//      .subscriptions({ (state, environment) -> [AnyHashable : Effect<AppAction, Never>] in
//
//      })
    )
//    Reducer<AppState, AppAction, AppEnvironment> { state, action, environment in
//      reducer(&state, action, environment)
//        .catch { error -> Effect<AppAction, Never> in
//          if case APIError.unauthorized = error {
//            return Just(AppAction.handleUnauthorized).eraseToEffect()
//          }
//
//          return Just(AppAction.showToast(error.localizedDescription)).eraseToEffect()
//        }
////        .append(AppAction.hideLoading)
//        .eraseToEffect()
//    }
  }
}

struct ToastViewContainer: View { // fixme: rename to ToastView
  static let outerPadding: CGFloat = 25
  let store: Store<AppState, AppAction>
  @State var autoDismissWorkItem: DispatchWorkItem?

  var body: some View {
    GeometryReader { proxy -> WithViewStore<AppState, AppAction, AnyView> in
      WithViewStore(self.store) { viewStore in
        guard viewStore.toastStatus.isShowing else { return AnyView(EmptyView()) } // fixme: will this work?

        return AnyView(
          ToastView(text: viewStore.toastStatus.text)
            .frame(width: proxy.size.width - (2 * Self.outerPadding))
            .position(x: proxy.size.width / 2)
            .offset(y: 60)
            .transition(AnyTransition.opacity.animation(.default))
            .onAppear {
              let workItem = DispatchWorkItem { viewStore.send(.hideToast) }
              self.autoDismissWorkItem = workItem
              DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
            }
            .onTapGesture {
              self.autoDismissWorkItem?.cancel()
              self.autoDismissWorkItem = nil
              viewStore.send(.hideToast)
            }
        )
      }
    }
  }

  struct ToastView: View {
    let text: String

    var body: some View {
      Text(text)
        .padding()
        .frame(minWidth: 0, maxWidth: .infinity)
        .foregroundColor(.white)
        .background(Color.gray.opacity(0.8))
        .cornerRadius(8)
    }
  }
}

// MARK: - Feature domain

struct EditProfileView: View {
  let store: Store<AppState, AppAction>
  @State var name: String = "Bob Loblaw"

  var body: some View {
    WithViewStore(self.store) { viewStore in
      ZStack {
        VStack {
          TextField("Name", text: self.$name)
          Button("Save") { viewStore.send(.saveName(self.name)) }
          if viewStore.isLoading {
            Image(systemName: "tortoise")
          }
        }
        ToastViewContainer(store: self.store)
      }
    }
  }
}

struct Fixme_Previews: PreviewProvider {
  static var previews: some View {
    EditProfileView(
      store: Store(
        initialState: AppState(),
        reducer: Reducer<AppState, AppAction, AppEnvironment>.errorHandling(appReducer),
        environment: AppEnvironment()
      )
    )
  }
}

enum ProfileError: Error {
  case unknown
}

struct ProfileState: Equatable {
  var name: String
//  var isSaving: Bool = false
}

enum ProfileAction {
  case saveName(String)
  case savedName(String)
}

struct ProfileEnvironment {
  var mainQueue: AnySchedulerOf<DispatchQueue> = DispatchQueue.main.eraseToAnyScheduler()
  var saveProfile: () -> AnyPublisher<Void, Error> = {
    Fail(outputType: Void.self, failure: ProfileError.unknown).eraseToAnyPublisher()
  }
}

//let profileReducer = Reducer<ProfileState, ProfileAction, ProfileEnvironment> { state, action, environment in
//  switch action {
//  case .saveName(let name):
//    return environment.saveProfile()
//      .receive(on: environment.mainQueue)
//      .map { ProfileAction.savedName(name) }
//
//  case .savedName(let name):
//    state.name = name
//    return .none
//  }
//}

