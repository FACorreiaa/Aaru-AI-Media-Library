import {
  FileField,
  FileFieldHiddenInput,
  FileFieldTrigger,
} from '~/components/ui'

const PHOTO_TYPES = 'image/jpeg,image/png,image/gif,image/webp,image/heic'

/** Profile → Add or Change photo (SOC-001b). Its own chunk: Account loads without the file field. */
export default function PhotoPicker(props: {
  label: string
  disabled: boolean
  onPick: (file: File) => void
  onReject: () => void
}) {
  return (
    <FileField
      accept={PHOTO_TYPES}
      maxFiles={1}
      disabled={props.disabled}
      onFileAccept={(files) => {
        const file = files.at(0)
        if (file) props.onPick(file)
      }}
      onFileReject={() => props.onReject()}
    >
      <FileFieldHiddenInput />
      <FileFieldTrigger variant="outline" size="sm">
        {props.label}
      </FileFieldTrigger>
    </FileField>
  )
}
