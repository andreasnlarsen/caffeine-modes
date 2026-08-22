public enum TravelCountdownFormatter {
    public static func string(seconds: Int) -> String {
        let totalMinutes = max(0, seconds + 59) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
