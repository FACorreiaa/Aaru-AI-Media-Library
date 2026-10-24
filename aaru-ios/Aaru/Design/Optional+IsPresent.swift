extension Optional {
    /// For `.alert(isPresented:)` over an optional message: true while there is one; setting
    /// false clears it.
    var isPresent: Bool {
        get { self != nil }
        set {
            if !newValue {
                self = nil
            }
        }
    }
}
