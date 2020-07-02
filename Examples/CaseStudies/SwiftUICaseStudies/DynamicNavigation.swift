import ComposableArchitecture
import SwiftUI

struct DNState: Equatable {
    var list: [String] = ["a", "b", "c"]
    var selection: String?
}

enum DNAction: Equatable {
    case updateSelection(String?)
    case moveToNext
}

let DNReducer = Reducer<DNState, DNAction, Void> { state, action, _ in
    switch action {
    case .updateSelection(let selection):
        state.selection = selection
    case .moveToNext:
        guard
            let selection = state.selection,
            let currentIndex = state.list.firstIndex(of: selection)
        else {
            assertionFailure()
            return .none
        }

        let nextIndex = currentIndex + 1
        if nextIndex < state.list.endIndex {
            state.selection = state.list[nextIndex]
        } else {
            state.selection = state.list[0]
        }
    }

    return .none
}.debugActions()

struct DNView: View {
    @State var list: [String] = ["a", "b", "c"]
    @State var selection: String? = nil

    var body: some View {
        List {
            ForEach(self.list, id: \.self) { item in
                NavigationLink(
                    destination: DNDetailView(selection: self.$selection),
                    tag: item,
                    selection: Binding<String?>(
                        get: { self.selection },
                        set: { newValue in
                            print("CHANGE SELECTION FROM: \(self.selection) TO: \(newValue)")
                            self.selection = newValue
                        }
                    )
                    )
                {
                    Text(item)
                }.isDetailLink(false)
            }
        }
    }
}

struct DNDetailView: View {
    @Binding var selection: String?

    var body: some View {
        VStack {
            Text(selection ?? "nil")
            Button(action: {
                self.selection = "b"
            }) {
                Text("Next")
            }
        }.onAppear {
            print(self.selection)
        }
    }
}
