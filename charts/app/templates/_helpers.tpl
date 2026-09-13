{{/*
Expand the name of the chart.
*/}}
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name, honoring fullnameOverride/nameOverride.
*/}}
{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "app.labels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name: explicit override, else fullname when create is true, else "default".
*/}}
{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "app.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Deployment strategy mode (rolling | canary | blueGreen). Default rolling.
*/}}
{{- define "app.strategyMode" -}}
{{- default "rolling" .Values.strategy.mode -}}
{{- end -}}

{{/*
Canary Deployment/Service name.
*/}}
{{- define "app.canary.fullname" -}}
{{- printf "%s-canary" (include "app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Canary selector labels — distinct instance so canary pods never join the stable Service.
*/}}
{{- define "app.canary.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ printf "%s-canary" .Release.Name | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/track: canary
{{- end -}}

{{/*
Blue/green slot Deployment name. Usage: include "app.slot.fullname" (dict "root" . "slot" "blue")
*/}}
{{- define "app.slot.fullname" -}}
{{- printf "%s-%s" (include "app.fullname" .root) .slot | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Blue/green slot selector labels. Usage: include "app.slot.selectorLabels" (dict "root" . "slot" "blue")
*/}}
{{- define "app.slot.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/slot: {{ .slot }}
{{- end -}}

{{/*
Resolved canary Ingress host: canary.ingress.host, else canary.<ingress.host>.
*/}}
{{- define "app.canary.ingressHost" -}}
{{- if .Values.canary.ingress.host -}}
{{- .Values.canary.ingress.host -}}
{{- else if .Values.ingress.host -}}
{{- printf "canary.%s" .Values.ingress.host -}}
{{- else -}}
{{- end -}}
{{- end -}}

{{/*
Blue/green inactive slot (the one the Service does NOT select).
*/}}
{{- define "app.blueGreen.inactiveSlot" -}}
{{- if eq (default "blue" .Values.blueGreen.activeSlot) "blue" -}}green{{- else -}}blue{{- end -}}
{{- end -}}

{{/*
Blue/green preview Service/Ingress name (targets the inactive slot).
*/}}
{{- define "app.preview.fullname" -}}
{{- printf "%s-preview" (include "app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolved blue/green preview Ingress host: blueGreen.preview.ingress.host, else preview.<ingress.host>.
*/}}
{{- define "app.preview.ingressHost" -}}
{{- if .Values.blueGreen.preview.ingress.host -}}
{{- .Values.blueGreen.preview.ingress.host -}}
{{- else if .Values.ingress.host -}}
{{- printf "preview.%s" .Values.ingress.host -}}
{{- end -}}
{{- end -}}

{{/*
Job/CronJob resource name.
Usage: include "app.job.fullname" (dict "root" . "name" "migrate" "suffix" "abc123")
*/}}
{{- define "app.job.fullname" -}}
{{- $base := printf "%s-%s" (include "app.fullname" .root) (.name | default "job") -}}
{{- if .suffix -}}
{{- printf "%s-%s" ($base | trunc 45 | trimSuffix "-") .suffix | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $base | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Shared Pod spec for Job/CronJob workloads. Inherits image/env/envFrom/resources and the
scheduling blocks from the top-level values; every field is overridable per job.
Usage: include "app.job.podSpec" (dict "root" $ "job" $jobValues) | nindent <n>
*/}}
{{- define "app.job.podSpec" -}}
{{- $root := .root -}}
{{- $job := .job -}}
{{- $img := $job.image | default dict -}}
{{- $repo := $img.repository | default $root.Values.image.repository -}}
{{- $tag := $img.tag | default $root.Values.image.tag -}}
{{- $pullPolicy := $img.pullPolicy | default $root.Values.image.pullPolicy -}}
{{- $env := concat ($root.Values.env | default list) ($job.env | default list) -}}
{{- $envFrom := concat ($root.Values.envFrom | default list) ($job.envFrom | default list) -}}
{{- $resources := $job.resources | default $root.Values.resources -}}
{{- $affinity := $job.affinity | default $root.Values.affinity -}}
{{- $tolerations := $job.tolerations | default $root.Values.tolerations -}}
{{- $nodeSelector := $job.nodeSelector | default $root.Values.nodeSelector -}}
restartPolicy: {{ $job.restartPolicy | default "Never" }}
{{- with $root.Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if or $root.Values.serviceAccount.create $root.Values.serviceAccount.name }}
serviceAccountName: {{ include "app.serviceAccountName" $root }}
{{- end }}
{{- with $affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: {{ $job.name | default "job" }}
    image: "{{ $repo }}:{{ $tag }}"
    imagePullPolicy: {{ $pullPolicy }}
    {{- with $job.command }}
    command:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $job.args }}
    args:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $env }}
    env:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $envFrom }}
    envFrom:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end -}}

{{/*
Shared Job spec body (everything under a Job's `spec:` except `template`).
Usage: include "app.job.spec" (dict "job" $jobValues) | nindent <n>
*/}}
{{- define "app.job.spec" -}}
{{- $job := .job -}}
backoffLimit: {{ $job.backoffLimit | default 0 }}
{{- if $job.ttlSecondsAfterFinished }}
ttlSecondsAfterFinished: {{ $job.ttlSecondsAfterFinished }}
{{- end }}
{{- if $job.activeDeadlineSeconds }}
activeDeadlineSeconds: {{ $job.activeDeadlineSeconds }}
{{- end }}
{{- if $job.parallelism }}
parallelism: {{ $job.parallelism }}
{{- end }}
{{- if $job.completions }}
completions: {{ $job.completions }}
{{- end }}
{{- end -}}

{{/*
Job/CronJob pod labels. The instance label is suffixed so job pods can never be selected
by the app Service (which matches name + instance).
Usage: include "app.job.podLabels" (dict "root" . "name" "migrate")
*/}}
{{- define "app.job.podLabels" -}}
app.kubernetes.io/name: {{ include "app.name" .root }}
app.kubernetes.io/instance: {{ printf "%s-%s" .root.Release.Name (.name | default "job") | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/component: job
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}
