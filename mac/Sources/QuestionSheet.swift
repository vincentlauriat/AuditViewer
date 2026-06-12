import SwiftUI

struct QuestionSheet: View {
    let question: AuditQuestion
    @Environment(AuditStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude a besoin de votre avis")
                        .font(.headline)
                    Text("Étape de l'audit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider().padding(.vertical, 16)

            // Texte de la question (le multiline text du skill)
            Text(question.text)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Spacer().frame(height: 16)

            // Boutons de réponse
            VStack(spacing: 8) {
                ForEach(question.options, id: \.value) { option in
                    Button {
                        store.answerQuestion(value: option.value)
                        dismiss()
                    } label: {
                        Text(option.label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
