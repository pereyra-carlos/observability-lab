# Diagramas

## 1 — Los workloads de Vantia

Lo que la empresa tiene corriendo. Es lo que hay que observar; todavía no hay observabilidad acá.

```mermaid
flowchart LR
    gen["generador de tráfico<br/><i>simula clientes</i>"]
    gw["vantia-gateway<br/><small>valida tenant<br/>genera request_id</small>"]
    ret["vantia-retrieval<br/><small>busca en la KB<br/>arma el contexto</small>"]
    wrk["vantia-llm-worker<br/><small>llama al modelo<br/>arma la respuesta</small>"]
    redis[("Redis<br/><small>cola</small>")]

    gen -->|"HTTP POST /ask"| gw
    gw -->|"q:retrieval"| redis
    redis --> ret
    ret -->|"q:llm"| redis
    redis --> wrk
    wrk -.->|"respuesta"| gen

    classDef svc fill:#2478CC,stroke:#1a5a99,color:#fff
    classDef infra fill:#6b7280,stroke:#4b5563,color:#fff
    classDef ext fill:#C45D3E,stroke:#9c4a32,color:#fff
    class gw,ret,wrk svc
    class redis infra
    class gen ext
```

**El problema que esto crea**: una sola consulta del cliente deja rastro en **tres procesos
distintos**, cada uno con su archivo de log, y todos se pierden cuando el pod reinicia. El
`request_id` que genera el gateway y arrastra por la cola es lo único que después permite volver a
juntarlos.

## 2 — La observabilidad, fase por fase

### Fase 0 — hoy (el punto de partida)

```mermaid
flowchart LR
    p["pods de vantia"] --> f["/var/log/containers/*.log<br/><small>en el disco del nodo</small>"]
    f -.->|"kubectl logs"| h["vos, a mano,<br/>de a un pod"]
    f -->|"el pod reinicia"| x["se pierde"]

    classDef bad fill:#b91c1c,stroke:#7f1d1d,color:#fff
    class x bad
```

### Fase 1 — logs centralizados y correlacionados

**Estado hoy: la fase 1 está cerrada.** Todo verde.

```mermaid
flowchart LR
    p["pods de vantia<br/><small>8 pods · log JSON con request_id</small>"]
    f["/var/log/containers<br/><small>disco del nodo</small>"]
    fb["Fluent Bit<br/><small>DaemonSet · 3 nodos</small>"]
    os[("OpenSearch<br/><small>alias logs-k8s</small>")]
    tpl["index template + ISM<br/><small>hot→warm→delete</small>"]
    d["Dashboards<br/><small>:30832</small>"]

    p --> f --> fb --> os --> d
    tpl --> os

    classDef hecho fill:#16a34a,stroke:#15803d,color:#fff
    class p,f,fb,os,tpl,d hecho
```

Ya no hay una caja roja de «a mano, pod por pod»: una búsqueda por `request_id` devuelve la
conversación entera, ordenada, y sobrevive al reinicio de los pods.

**Estado objetivo** de la fase:

```mermaid
flowchart LR
    p["pods de vantia"] --> f["/var/log/containers"]
    f --> fb["Fluent Bit<br/><small>DaemonSet, 1 por nodo</small>"]

    subgraph fbin ["dentro de Fluent Bit"]
        direction TB
        i["INPUT tail<br/><small>parser CRI · Exclude_Path</small>"] --> k["FILTER kubernetes<br/><small>pega pod/ns/contenedor</small>"]
        k --> pr["PARSER custom<br/><small>abre el JSON de Vantia</small>"]
    end

    fb --- fbin

    subgraph oss ["OpenSearch"]
        direction TB
        al["alias de escritura<br/><small>logs-k8s</small>"] --> idx[("logs-k8s-000001<br/><small>replicas: 0</small>")]
        ism["política ISM<br/><small>hot → warm → delete</small>"] -.->|"rollover"| idx
    end

    fbin --> al
    idx --> d["Dashboards<br/><small>la búsqueda</small>"]

    classDef new fill:#16a34a,stroke:#15803d,color:#fff
    class fb,d,fbin,oss new
```

Dos detalles del dibujo que salieron de construirlo, y que no son decorativos:

- **`Exclude_Path` está en el INPUT, no en un filtro.** Si el descarte ocurriera después, Fluent Bit
  pagaría igual el costo de leer y de consultarle al API server la metadata de cada pod para tirarla
  a la basura. Y filtrar ahí es lo que evita que ingiera sus propios logs y los de OpenSearch, que se
  retroalimentan.
- **Fluent Bit escribe contra un alias, no contra un índice.** Es lo que permite que el rollover
  cambie el índice de destino por debajo sin tocar la configuración de Fluent Bit ni reiniciarlo.

**Lo que se cierra**: una búsqueda por `request_id` devuelve las líneas de los tres servicios, en
orden, sobrevive al reinicio de los pods y dura lo que diga la política de retención.

### Fase 2 — un pipeline, dos destinos

```mermaid
flowchart LR
    fb["Fluent Bit"] --> os[("OpenSearch<br/><small>compliance · 1 año</small>")]
    fb --> lk[("Loki<br/><small>operación · barato</small>")]
    os --> d["Dashboards"]
    os --> g["Grafana"]
    lk --> g

    classDef new fill:#16a34a,stroke:#15803d,color:#fff
    class lk,g new
```

**Por qué dos**: no es comparar por deporte. OpenSearch está porque compliance pide un año buscable;
Loki porque ingeniería no quiere salir de Grafana y el costo a un año no cierra. Dos dueños, dos
motivos, **un solo pipeline** alimentándolos.

### Fase 2 — trazas (dolor cerrado, falta el post)

**Estado hoy**: el camino está completo y llega a Grafana. Falta demostrar la correlación.

```mermaid
flowchart LR
    subgraph app ["servicios de Vantia · imagen 0.2.0"]
        gw["gateway<br/><small>gateway.ask</small>"] --> ret["retrieval<br/><small>retrieval.search</small>"] --> wrk["llm-worker<br/><small>llm.generate</small>"]
    end

    app -->|"OTLP :4317"| col["OTel Collector<br/><small>k8s_attributes</small>"]
    col --> tp[("Tempo<br/><small>single binary · 24h</small>")]
    tp --> g["Grafana :30833"]
    os[("OpenSearch<br/><small>logs con trace_id</small>")] --> g

    tp -.->|"tracesToLogsV2"| os
    os -.->|"dataLink por trace_id"| tp

    classDef hecho fill:#16a34a,stroke:#15803d,color:#fff
    classDef falta fill:#e5e7eb,stroke:#9ca3af,color:#4b5563,stroke-dasharray: 4 3
    class gw,ret,wrk,col,tp,g,os hecho
```

**El contexto viaja dentro del mensaje de la cola**, igual que el `request_id` de la fase 1 — pero
ahora con `inject`/`extract` del estándar en vez de a mano. Verificado: los tres servicios comparten
`trace_id` y difieren en `span_id`.

Las dos flechas de la correlación están **demostradas**: desde un log se llega a su traza
(`queryType=traceId` devuelve los 3 spans) y desde una traza a sus logs (`trace_id:"..."` devuelve las
3 líneas). El dashboard `Vantia — one request, both signals` pone las dos cosas en una pantalla.

### Fase 4 — métricas de negocio: tokens y costo

```mermaid
flowchart LR
    app["servicios de Vantia"] -->|"OTLP métricas"| col["OTel Collector"]
    col --> mi[("Mimir")]
    mi --> g["Grafana"]
    g --> q["'¿qué tenant<br/>subió la factura?'"]

    classDef new fill:#16a34a,stroke:#15803d,color:#fff
    class mi,q new
```

### Fase 5 — las tres señales sobre una misma request

```mermaid
flowchart TB
    r["una request<br/><small>trace_id</small>"]
    r --> t[("Tempo<br/>trazas")]
    r --> l[("Loki / OpenSearch<br/>logs")]
    r --> m[("Mimir<br/>métricas")]
    t <-->|"trace → logs"| l
    t <-->|"exemplars"| m
    t --> g["Grafana<br/><small>una pantalla</small>"]
    l --> g
    m --> g
    g --> a["alerta que abre<br/>en el lugar correcto"]

    classDef new fill:#16a34a,stroke:#15803d,color:#fff
    class g,a new
```
