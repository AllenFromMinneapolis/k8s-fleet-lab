{{- define "fleet.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  retry:
    limit: 20
    backoff:
      duration: 15s
      factor: 2
      maxDuration: 3m
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - SkipDryRunOnMissingResource=true
{{- end -}}
