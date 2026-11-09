module common.content.exporting;

import core.stdc.math : fabs, floor;
import core.stdc.stdlib : strtod;
import base.maybe : MaybeIndex;
import base.stdio : FILE, fprintf, snprintf;
import common.content.declarations : FieldDecl, Presence, ValueType;
import common.content.graph : Attribute, ContentEdge, ContentGraph, Range, Standing, ValueKind;
import common.content.settings : MOD_KIND;
import plugins.api.content : ContentRef, Holder, Need;

enum uint MOST_DIGITS = 17;
enum size_t NUMBER_CAPACITY = 32;
enum double LARGEST_WHOLE = 1e15;

bool isPlain(char c) {
    return c != '"' && c != '\\' && c >= ' ';
}

void writeEscaped(FILE* output, const(char)[] text) {
    size_t start = 0;
    while (start < text.length) {
        size_t end = start;
        while (end < text.length && isPlain(text[end])) {
            end += 1;
        }
        fprintf(output, "%.*s", cast(int)(end - start), text.ptr + start);
        if (end < text.length) {
            writeEscape(output, text[end]);
            end += 1;
        }
        start = end;
    }
}

void writeEscape(FILE* output, char c) {
    if (c == '"' || c == '\\') {
        fprintf(output, "\\%c", c);
    } else if (c == '\n') {
        fprintf(output, "\\n");
    } else {
        fprintf(output, "\\u%04x", cast(uint) c);
    }
}

void writeQuoted(FILE* output, const(char)[] text) {
    fprintf(output, "\"");
    writeEscaped(output, text);
    fprintf(output, "\"");
}

void writeAttributes(FILE* output, ref const ContentGraph graph, Range range) {
    fprintf(output, "{");
    foreach (index; range.first .. range.end) {
        const(Attribute)* attribute = &graph.attributes.ptr[index];
        if (index > range.first) {
            fprintf(output, ", ");
        }
        writeQuoted(output, graph.textOf(attribute.key));
        fprintf(output, ": ");
        final switch (attribute.value) {
            case ValueKind.number:
                fprintf(output, "%.15g", attribute.number);
                break;
            case ValueKind.text:
                writeQuoted(output, graph.textOf(attribute.text));
                break;
        }
    }
    fprintf(output, "}");
}

void writeGraphJson(FILE* output, ref const ContentGraph graph) {
    fprintf(output, "{\n  \"nodes\": [");
    size_t written = 0;
    foreach (index, ref node; graph.nodes.slice()) {
        if (node.standing == Standing.kept) {
            if (written > 0) {
                fprintf(output, ",");
            }
            fprintf(output, "\n    {\"name\": ");
            writeQuoted(output, graph.textOf(node.name));
            fprintf(output, ", \"kind\": ");
            writeQuoted(output, graph.textOf(node.kind));
            fprintf(output, ", \"owner\": ");
            writeQuoted(output, graph.textOf(node.owner));
            fprintf(output, ", \"attributes\": ");
            writeAttributes(output, graph, graph.nodeAttributes.ptr[index]);
            fprintf(output, "}");
            written += 1;
        }
    }
    fprintf(output, "\n  ],\n  \"edges\": [");
    written = 0;
    foreach (index, ref edge; graph.edges.slice()) {
        if (edge.standing == Standing.kept) {
            if (written > 0) {
                fprintf(output, ",");
            }
            fprintf(output, "\n    {\"kind\": ");
            writeQuoted(output, graph.textOf(edge.kind));
            fprintf(output, ", \"from\": ");
            writeQuoted(output, graph.textOf(edge.fromName));
            fprintf(output, ", \"to\": ");
            writeQuoted(output, graph.textOf(edge.toName));
            fprintf(output, ", \"owner\": ");
            writeQuoted(output, graph.textOf(edge.owner));
            fprintf(output, ", \"attributes\": ");
            writeAttributes(output, graph, graph.edgeAttributes.ptr[index]);
            fprintf(output, "}");
            written += 1;
        }
    }
    fprintf(output, "\n  ],\n  \"problems\": [");
    foreach (index, ref problem; graph.problems.slice()) {
        if (index > 0) {
            fprintf(output, ",");
        }
        fprintf(output, "\n    {\"owner\": ");
        writeQuoted(output, graph.textOf(problem.owner));
        fprintf(output, ", \"message\": ");
        writeQuoted(output, problem.message);
        fprintf(output, "}");
    }
    fprintf(output, "\n  ]\n}\n");
}

void writeNumber(FILE* output, double value) {
    char[NUMBER_CAPACITY] text;
    uint digits = 1;
    if (floor(value) == value && fabs(value) < LARGEST_WHOLE) {
        snprintf(text.ptr, text.length, "%.0f", value);
    } else {
        snprintf(text.ptr, text.length, "%.*g", digits, value);
        while (digits < MOST_DIGITS && !isSameNumber(strtod(text.ptr, null), value)) {
            digits += 1;
            snprintf(text.ptr, text.length, "%.*g", digits, value);
        }
    }
    fprintf(output, "%s", text.ptr);
}

bool isSameNumber(double parsed, double value) {
    if (cast(double) cast(float) value == value) {
        return cast(float) parsed == cast(float) value;
    } else {
        return parsed == value;
    }
}

void writeValue(FILE* output, ref const ContentGraph graph, ref const Attribute attribute) {
    final switch (attribute.value) {
        case ValueKind.number:
            writeNumber(output, attribute.number);
            break;
        case ValueKind.text:
            writeQuoted(output, graph.textOf(attribute.text));
            break;
    }
}

bool isDefault(ref const FieldDecl field, ref const Attribute attribute) {
    if (field.presence != Presence.defaulted) {
        return false;
    } else if (field.type == ValueType.number || field.type == ValueType.integer) {
        return attribute.value == ValueKind.number && attribute.number == field.fallbackNumber;
    } else {
        return attribute.value == ValueKind.text && attribute.text == field.fallbackText;
    }
}

bool isWritten(ref const ContentGraph graph, Holder holding, MaybeIndex!uint declHolder, ref const Attribute attribute) {
    if (!declHolder.exists) {
        return true;
    } else {
        MaybeIndex!uint field = graph.declarations.fieldOf(holding, declHolder.value, attribute.key);
        return !field.exists || !isDefault(graph.declarations.fields.ptr[field.value], attribute);
    }
}

bool isOwnedBy(uint owner, ref const ContentGraph graph, const(char)[][] mods) {
    size_t index = 0;
    while (index < mods.length && graph.textOf(owner) != mods[index]) {
        index += 1;
    }
    return mods.length == 0 || index < mods.length;
}

const(char)[] arrowOf(Need need) {
    final switch (need) {
        case Need.required:
            return "->";
        case Need.optional:
            return "?->";
    }
}

bool isListed(ref const ContentGraph graph, uint edge) {
    return graph.edgeAttributes.ptr[edge].first == graph.edgeAttributes.ptr[edge].end;
}

bool isSameRun(ref const ContentGraph graph, uint a, uint b) {
    return graph.edges.ptr[a].kind == graph.edges.ptr[b].kind && graph.edges.ptr[a].need == graph.edges.ptr[b].need && graph.edges.ptr[a].owner == graph.edges.ptr[b].owner && isListed(graph, a) && isListed(graph, b);
}

void writeEdges(FILE* output, ref const ContentGraph graph, uint node, const(char)[][] mods) {
    const(uint)[] leaving = graph.edgesFrom(node);
    size_t start = 0;
    while (start < leaving.length) {
        size_t end = start + 1;
        while (end < leaving.length && isSameRun(graph, leaving[start], leaving[end])) {
            end += 1;
        }
        const(ContentEdge)* first = &graph.edges.ptr[leaving[start]];
        if (isOwnedBy(first.owner, graph, mods)) {
            const(char)[] kind = graph.textOf(first.kind);
            const(char)[] arrow = arrowOf(first.need);
            fprintf(output, "    %.*s %.*s ", cast(int) kind.length, kind.ptr, cast(int) arrow.length, arrow.ptr);
            if (end - start > 1) {
                fprintf(output, "[");
                foreach (index; start .. end) {
                    const(char)[] to = graph.textOf(graph.edges.ptr[leaving[index]].toName);
                    if (index > start) {
                        fprintf(output, " ");
                    }
                    fprintf(output, "%.*s", cast(int) to.length, to.ptr);
                }
                fprintf(output, "]");
            } else {
                const(char)[] to = graph.textOf(first.toName);
                fprintf(output, "%.*s", cast(int) to.length, to.ptr);
                writeEdgeAttributes(output, graph, leaving[start]);
            }
            fprintf(output, "\n");
        }
        start = end;
    }
}

void writeEdgeAttributes(FILE* output, ref const ContentGraph graph, uint edge) {
    const(ContentEdge)* record = &graph.edges.ptr[edge];
    MaybeIndex!uint decl = graph.declarations.edgeOf(graph.nodes.ptr[record.from].kind, record.kind);
    uint written = 0;
    foreach (ref attribute; graph.attributesOf(ContentRef(edge, Holder.edge))) {
        if (isWritten(graph, Holder.edge, decl, attribute)) {
            const(char)[] key = graph.textOf(attribute.key);
            if (written == 0) {
                fprintf(output, " { ");
            } else {
                fprintf(output, ", ");
            }
            fprintf(output, "%.*s: ", cast(int) key.length, key.ptr);
            writeValue(output, graph, attribute);
            written += 1;
        }
    }
    if (written > 0) {
        fprintf(output, " }");
    }
}

uint ownedEdgeCount(ref const ContentGraph graph, uint node, const(char)[][] mods) {
    uint count = 0;
    foreach (edge; graph.edgesFrom(node)) {
        if (isOwnedBy(graph.edges.ptr[edge].owner, graph, mods)) {
            count += 1;
        }
    }
    return count;
}

void writeGraphData(FILE* output, ref const ContentGraph graph, const(char)[][] mods) {
    foreach (index, ref node; graph.nodes.slice()) {
        uint at = cast(uint) index;
        bool owned = isOwnedBy(node.owner, graph, mods);
        if (node.standing == Standing.kept && graph.textOf(node.kind) != MOD_KIND && (owned || ownedEdgeCount(graph, at, mods) > 0)) {
            const(char)[] kind = graph.textOf(node.kind);
            const(char)[] name = graph.textOf(node.name);
            fprintf(output, "%.*s %.*s {\n", cast(int) kind.length, kind.ptr, cast(int) name.length, name.ptr);
            if (owned) {
                MaybeIndex!uint holder = MaybeIndex!uint.of(node.kind);
                foreach (ref attribute; graph.attributesOf(ContentRef(at, Holder.node))) {
                    if (isWritten(graph, Holder.node, holder, attribute)) {
                        const(char)[] key = graph.textOf(attribute.key);
                        fprintf(output, "    %.*s: ", cast(int) key.length, key.ptr);
                        writeValue(output, graph, attribute);
                        fprintf(output, "\n");
                    }
                }
            }
            writeEdges(output, graph, at, mods);
            fprintf(output, "}\n\n");
        }
    }
}

void writeGraphDot(FILE* output, ref const ContentGraph graph) {
    fprintf(output, "digraph content {\n");
    foreach (ref node; graph.nodes.slice()) {
        if (node.standing == Standing.kept) {
            fprintf(output, "  ");
            writeQuoted(output, graph.textOf(node.name));
            fprintf(output, " [label=\"");
            writeEscaped(output, graph.textOf(node.name));
            fprintf(output, "\\n");
            writeEscaped(output, graph.textOf(node.kind));
            fprintf(output, "\"];\n");
        }
    }
    foreach (ref edge; graph.edges.slice()) {
        if (edge.standing == Standing.kept) {
            fprintf(output, "  ");
            writeQuoted(output, graph.textOf(edge.fromName));
            fprintf(output, " -> ");
            writeQuoted(output, graph.textOf(edge.toName));
            fprintf(output, " [label=");
            writeQuoted(output, graph.textOf(edge.kind));
            fprintf(output, "];\n");
        }
    }
    fprintf(output, "}\n");
}
