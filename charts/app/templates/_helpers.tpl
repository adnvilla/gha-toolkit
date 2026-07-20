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
