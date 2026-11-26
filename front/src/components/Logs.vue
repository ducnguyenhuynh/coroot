<template>
    <div class="logs">
        <v-alert v-if="view.message" color="info" outlined text class="message">
            {{ view.message }}
        </v-alert>
        <template v-else>
            <v-alert v-if="view.error" color="error" icon="mdi-alert-octagon-outline" outlined text class="mt-2">
                {{ view.error }}
            </v-alert>

            <v-card outlined class="px-4 mb-2" :class="showSources ? 'py-2' : 'pt-2 pb-4'">
                <div class="subtitle-1">Query:</div>
                <div class="d-flex flex-wrap flex-md-nowrap gap-2">
                    <QueryBuilder
                        v-model="query.filters"
                        :loading="qb.loading"
                        :items="qb.items"
                        :error="qb.error"
                        :disabled="query.view !== 'messages'"
                        :hidden-attributes="hiddenAttributes"
                        @get="qbGet"
                        class="flex-grow-1"
                    />
                    <LogSearchButtons :interval="refreshInterval" @search="get" @refresh="setRefreshInterval" />
                </div>
                <div v-if="showSources" class="mt-3">
                    <ApplicationFilter :applications="appsWithLogs" @filter="appFilter = $event" class="mb-2" />
                    <div v-if="appPills.length" class="app-pills">
                        <div
                            v-for="a in appPills"
                            :key="a.id"
                            class="app-pill primary--text"
                            :class="{ active: isServiceActive(a.service) }"
                            :title="a.service"
                            @click="toggleService(a.service)"
                        >
                            <span class="status" :class="a.color" />
                            <span class="name">{{ a.name }}</span>
                            <AppIcon :icon="a.icon" />
                        </div>
                    </div>
                    <div v-else-if="!services.loading" class="caption grey--text">no applications with logs</div>
                </div>
                <div v-if="showSources" class="d-flex gap-2 sources">
                    <v-checkbox v-model="query.agent" label="Container logs" :disabled="disabled" dense hide-details />
                    <v-checkbox v-model="query.otel" label="OpenTelemetry" :disabled="disabled" dense hide-details />
                </div>
            </v-card>

            <Chart
                v-if="view.chart"
                :key="query.view"
                :chart="view.chart"
                :selection="{}"
                @select="zoom"
                @legend-click="showLegendMenu"
                class="my-3"
            />

            <v-menu v-model="legendMenu.show" :position-x="legendMenu.x" :position-y="legendMenu.y" absolute offset-y>
                <v-list dense>
                    <v-list-item @click="addLegendFilter('=')">
                        <v-icon small class="mr-1">mdi-plus</v-icon>
                        Show only {{ legendMenu.label }}
                    </v-list-item>
                    <v-list-item @click="addLegendFilter('!=')">
                        <v-icon small class="mr-1">mdi-minus</v-icon>
                        Exclude {{ legendMenu.label }}
                    </v-list-item>
                </v-list>
            </v-menu>

            <div v-if="query.view === 'messages'">
                <v-simple-table v-if="entries" :key="entries.length" dense class="entries">
                    <thead>
                        <tr>
                            <template v-for="col in columns">
                                <th :key="col.key" class="px-2">{{ col.label }}</th>
                            </template>
                        </tr>
                    </thead>
                    <tbody class="mono">
                        <tr v-for="(e, index) in entries" :key="`${e.timestamp}-${index}`" @click="entry = e" style="cursor: pointer">
                            <template v-for="col in cols">
                                <td :key="col.key" class="text-no-wrap px-2" :class="{ 'pl-0': col.key === columns[0].key }">
                                    <div v-if="col.key === 'date'" class="d-flex gap-1">
                                        <div class="marker" :style="{ backgroundColor: e.color }" />
                                        <div>{{ getColumnValue(e, col) }}</div>
                                    </div>
                                    <v-menu v-else-if="col.key === 'application'" offset-y @click.stop>
                                        <template #activator="{ on }">
                                            <a v-on="on" class="nowrap" style="display: inline-block; max-width: 20ch" @click.stop>{{
                                                getColumnValue(e, col)
                                            }}</a>
                                        </template>
                                        <v-list dense>
                                            <template v-if="e.attributes['service.name']">
                                                <v-list-item @click="qbAdd('service.name', '=', e.attributes['service.name'])">
                                                    <v-icon small class="mr-1">mdi-plus</v-icon>
                                                    add to search
                                                </v-list-item>
                                                <v-list-item @click="qbAdd('service.name', '!=', e.attributes['service.name'])">
                                                    <v-icon small class="mr-1">mdi-minus</v-icon>
                                                    exclude from search
                                                </v-list-item>
                                            </template>
                                            <v-list-item v-if="e.link" :to="e.link">
                                                <v-icon small class="mr-1">mdi-open-in-new</v-icon>
                                                go to application
                                            </v-list-item>
                                        </v-list>
                                    </v-menu>
                                    <div v-else>
                                        <span v-if="col.maxWidth" :title="getColumnValue(e, col)">
                                            {{ truncateText(getColumnValue(e, col), col.maxWidth) }}
                                        </span>
                                        <span v-else>{{ getColumnValue(e, col) }}</span>
                                    </div>
                                </td>
                            </template>
                        </tr>
                    </tbody>
                </v-simple-table>
                <div v-else-if="!loading" class="pa-3 text-center grey--text">No messages found</div>
                <div v-if="entries.length === query.limit" class="text-right caption grey--text mt-1">
                    The output is capped at
                    <InlineSelect v-model="query.limit" :items="limits" />
                    messages.
                </div>
                <LogEntry v-if="entry" v-model="entry" @filter="qbAdd" />
            </div>
        </template>
    </div>
</template>

<script>
import { palette } from '@/utils/colors';
import QueryBuilder from '@/components/QueryBuilder.vue';
import Chart from '@/components/Chart.vue';
import LogEntry from '@/components/LogEntry.vue';
import InlineSelect from '@/components/InlineSelect.vue';
import LogSearchButtons from '@/components/LogSearchButtons.vue';
import ApplicationFilter from '@/components/ApplicationFilter.vue';
import AppIcon from '@/components/AppIcon.vue';

const statusColors = {
    critical: 'red lighten-1',
    warning: 'orange lighten-1',
    info: 'blue lighten-1',
    unknown: 'purple lighten-1',
    ok: 'green lighten-1',
};

export default {
    components: { LogSearchButtons, InlineSelect, LogEntry, Chart, QueryBuilder, ApplicationFilter, AppIcon },

    props: {
        showSources: {
            type: Boolean,
            default: true,
        },
        defaultFilters: {
            type: Array,
            default: () => [],
        },
        hiddenAttributes: {
            type: Array,
            default: () => [],
        },
        columns: {
            type: Array,
            default: () => [
                { key: 'date', label: 'Date' },
                { key: 'cluster', label: 'Cluster', maxWidth: 20 },
                { key: 'application', label: 'Application' },
                { key: 'message', label: 'Message' },
            ],
        },
    },
    data() {
        let q = {};
        try {
            q = JSON.parse(this.$route.query.query || '{}');
        } catch {
            //
        }
        return {
            loading: false,
            error: '',
            view: {},
            refreshInterval: 0,
            query: this.makeQuery(q),
            limits: [10, 20, 50, 100, 1000, 5000, 10000],
            entry: null,
            qb: {
                loading: false,
                error: '',
                items: [],
            },
            legendMenu: {
                show: false,
                x: 0,
                y: 0,
                label: '',
                field: '',
                value: '',
            },
            services: {
                loading: false,
                items: [],
            },
            apps: [],
            appFilter: new Set(),
        };
    },

    mounted() {
        this.get();
        this.$events.watch(this, this.get, 'refresh');
    },

    beforeDestroy() {
        this.refreshInterval = 0;
    },

    watch: {
        $route: {
            handler(newRoute, oldRoute) {
                const raw = newRoute.query.query;
                if (raw !== oldRoute?.query.query && raw !== JSON.stringify(this.query)) {
                    let q = {};
                    try {
                        q = JSON.parse(this.$route.query.query || '{}');
                    } catch {
                        //
                    }
                    this.query = this.makeQuery(q);
                }
            },
        },
        query: {
            handler(curr, prev) {
                this.setQuery(curr.view !== prev.view);
                this.get();
            },
            deep: true,
        },
        loading(val) {
            this.$emit('loading', val);
        },
        error(val) {
            this.$emit('error', val);
        },
    },

    computed: {
        cols() {
            return this.columns;
        },
        queryWithDefaults() {
            return {
                ...this.query,
                filters: [...this.defaultFilters, ...this.query.filters],
            };
        },
        entries() {
            if (!this.view.entries) {
                return [];
            }
            const sorted = [...this.view.entries].sort((a, b) => b.timestamp - a.timestamp);
            if (sorted.length > this.query.limit) {
                sorted.splice(this.query.limit);
            }
            return sorted.map((e) => {
                const message = e.message.trim();
                const newline = message.indexOf('\n');
                let application = e.application;
                let link;
                if (e.application.includes(':')) {
                    const id = this.$utils.appId(e.application);
                    application = id.name;
                    link = {
                        name: 'overview',
                        params: { view: 'applications', id: e.application, report: 'Logs' },
                        query: this.$utils.contextQuery(),
                    };
                }
                return {
                    ...e,
                    application,
                    link,
                    message,
                    color: palette.get(e.color),
                    date: this.$format.date(e.timestamp, '{MMM} {DD} {HH}:{mm}:{ss}'),
                    multiline: newline > 0 ? newline : 0,
                };
            });
        },
        disabled() {
            return this.loading || this.query.view !== 'messages';
        },
        appsWithLogs() {
            const apps = [];
            this.apps.forEach((a) => {
                const name = this.$utils.appId(a.id).name;
                const service = this.services.items.find((s) => s === name || s.endsWith('/' + name));
                if (!service) return;
                apps.push({
                    ...a,
                    name,
                    service,
                    color: statusColors[a.status] || 'grey lighten-1',
                    icon: a.type ? a.type.icon : '',
                });
            });
            return apps.sort((a, b) => a.name.localeCompare(b.name));
        },
        appPills() {
            return this.appsWithLogs.filter((a) => this.appFilter.has(a.id));
        },
    },

    methods: {
        makeQuery(q) {
            return {
                view: q.view || 'messages',
                agent: q.agent !== undefined ? q.agent : true,
                otel: q.otel !== undefined ? q.otel : true,
                filters: q.filters || [],
                limit: q.limit || 100,
            };
        },
        setQuery(push) {
            const to = { query: { ...this.$route.query, query: JSON.stringify(this.query) } };
            if (push) {
                this.$router.push(to).catch((err) => err);
            } else {
                this.$router.replace(to).catch((err) => err);
            }
        },
        openView(v) {
            this.query.view = v;
        },
        qbAdd(name, op, value) {
            this.query.view = 'messages';
            this.entry = null;
            this.pattern = null;
            this.query.filters.push({ name, op, value });
        },
        qbGet(what, name) {
            this.qb.items = [];
            if (what === 'op') {
                switch (name) {
                    case 'Severity':
                        this.qb.items = ['=', '!='];
                        break;
                    case 'Message':
                        this.qb.items = ['contains', 'not contains'];
                        break;
                    case 'TraceId':
                    case 'pattern.hash':
                        this.qb.items = ['='];
                        break;
                    default:
                        this.qb.items = ['=', '!=', '~', '!~'];
                }
                return;
            }
            if (what === 'name') {
                this.qb.items = this.view.suggest || [];
                return;
            }
            this.qb.loading = true;
            this.qb.error = '';
            const query = JSON.stringify({ ...this.queryWithDefaults, suggest: name });
            this.$api.getOverview('logs', query, (data, error) => {
                this.qb.loading = false;
                if (error || data.status === 'warning') {
                    this.qb.error = error || data.message;
                    return;
                }
                this.qb.items = data.logs.suggest || [];
            });
        },
        get() {
            this.refreshInterval = 0;
            this.loading = true;
            this.error = '';
            this.$api.getOverview('logs', JSON.stringify(this.queryWithDefaults), (data, error) => {
                this.loading = false;
                if (error) {
                    this.error = error;
                    return;
                }
                this.view = data.logs || {};
            });
            if (this.showSources) {
                this.getServices();
                this.getApps();
            }
        },
        getApps() {
            this.$api.getOverview('applications', '', (data, error) => {
                if (error) return;
                this.apps = data.applications || [];
            });
        },
        getServices() {
            this.services.loading = true;
            const filters = this.queryWithDefaults.filters.filter((f) => f.name !== 'service.name');
            this.$api.getOverview('logs', JSON.stringify({ ...this.queryWithDefaults, filters, suggest: 'service.name' }), (data, error) => {
                this.services.loading = false;
                if (error || data.status === 'warning') {
                    this.services.items = [];
                    return;
                }
                this.services.items = (data.logs?.suggest || []).filter(Boolean);
            });
        },
        isServiceActive(name) {
            return this.query.filters.some((f) => f.name === 'service.name' && f.op === '=' && f.value === name);
        },
        toggleService(name) {
            if (this.isServiceActive(name)) {
                this.query.filters.splice(
                    this.query.filters.findIndex((f) => f.name === 'service.name' && f.op === '=' && f.value === name),
                    1,
                );
            } else {
                for (let i = this.query.filters.length - 1; i >= 0; i--) {
                    if (this.query.filters[i].name === 'service.name' && this.query.filters[i].op === '=') {
                        this.query.filters.splice(i, 1);
                    }
                }
                this.query.filters.push({ name: 'service.name', op: '=', value: name });
            }
            this.query.view = 'messages';
            this.entry = null;
        },
        startRefresh(interval) {
            if (this.$route.query.to) {
                this.$route.query.to = undefined;
                this.setQuery(false);
            }
            let since = this.view.max_ts || '';
            const refresh = () => {
                if (!this.refreshInterval) return;
                if (document.hidden) {
                    setTimeout(refresh, interval);
                    return;
                }
                this.loading = true;
                this.error = '';
                const query = { ...this.queryWithDefaults, since };
                const started = Date.now();
                this.$api.getOverview('logs', JSON.stringify(query), (data, error) => {
                    this.loading = false;
                    const elapsed = Date.now() - started;
                    setTimeout(refresh, Math.max(0, interval - elapsed));
                    if (error) {
                        this.error = error;
                        return;
                    }
                    this.view.error = data.logs.error;
                    this.view.message = data.logs.message;
                    this.view.chart = data.logs.chart;
                    if (data.logs.max_ts) {
                        since = data.logs.max_ts;
                    }
                    if (data.logs.entries) {
                        this.view.entries.push(...data.logs.entries);
                    }
                });
            };
            refresh();
        },
        setRefreshInterval(interval) {
            this.refreshInterval = interval;
            this.refreshInterval && this.startRefresh(this.refreshInterval * 1000);
        },
        zoom(s) {
            const { from, to } = s.selection;
            const query = { ...this.$route.query, from, to };
            this.$router.push({ query }).catch((err) => err);
        },
        getColumnValue(entry, column) {
            switch (column.key) {
                case 'date':
                    return entry.date;
                case 'application':
                    return entry.application;
                case 'message':
                    return entry.multiline ? entry.message.substr(0, entry.multiline) : entry.message;
                case 'cluster':
                    return entry.cluster;
                default:
                    // For custom attributes, look in the entry.attributes
                    return entry.attributes[column.key] || '';
            }
        },
        truncateText(text, maxLength) {
            if (!text) return '';
            return text.length > maxLength ? text.substring(0, maxLength) + '...' : text;
        },
        showLegendMenu(event) {
            this.legendMenu = {
                show: true,
                x: event.x,
                y: event.y,
                field: 'Severity',
                value: event.value,
                label: event.label || event.value,
            };
        },
        addLegendFilter(operator) {
            this.legendMenu.show = false;

            const sameFilterFound = this.query.filters.find(
                (f) => f.name === this.legendMenu.field && f.op === operator && f.value === this.legendMenu.value,
            );

            if (sameFilterFound) {
                return;
            }
            const conflictingFilter = this.query.filters.find((f) => f.name === this.legendMenu.field && f.value === this.legendMenu.value);

            if (conflictingFilter) {
                const index = this.query.filters.indexOf(conflictingFilter);
                this.query.filters.splice(index, 1, {
                    name: this.legendMenu.field,
                    op: operator,
                    value: this.legendMenu.value,
                });
            } else {
                this.qbAdd(this.legendMenu.field, operator, this.legendMenu.value);
            }
        },
    },
};
</script>

<style scoped>
.view {
    color: var(--text-color-dimmed);
}
.view.active {
    color: var(--text-color);
    border-bottom: 2px solid var(--text-color);
}
.sources:deep(.v-input--selection-controls__input) {
    margin-right: 0 !important;
}
.app-pills {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(190px, 1fr));
    gap: 6px;
    max-height: 160px;
    overflow-y: auto;
}
.app-pill {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 3px 8px;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
}
.app-pill:hover {
    border-color: currentColor;
}
.app-pill.active {
    border-color: currentColor;
    background-color: rgba(25, 118, 210, 0.12);
    font-weight: 500;
}
.app-pill .status {
    flex: none;
    width: 10px;
    height: 10px;
    border-radius: 50%;
}
.app-pill .name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
.mono {
    font-family: monospace, monospace;
}
.marker {
    height: 20px;
    width: 4px;
    filter: brightness(var(--brightness));
}
*:deep(.v-list-item) {
    min-height: 32px !important;
    padding: 0 8px !important;
}
</style>
