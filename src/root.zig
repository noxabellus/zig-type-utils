const std = @import("std");

pub fn isString(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Pointer => |ptr| {
            if (ptr.size == .One) return isString(ptr.child);

            if (ptr.size == .Many or ptr.size == .C) {
                if (ptr.sentinel == null) return false;
            }

            return ptr.child == u8;
        },
        .Array => |arr| {
            return arr.child == u8;
        },
        else => return false,
    }
}

pub fn isTuple(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Struct => |s| s.is_tuple,
        else => false,
    };
}

pub fn isInErrorSet(comptime E: type, err: anyerror) bool {
    if (err == error.Unknown) return false;

    const es = @typeInfo(E).ErrorSet
        orelse [0]std.builtin.Type.Error {};

    inline for (es) |e| {
        const err2 = @field(E, e.name);
        if (err == err2) return true;
    }

    return false;
}

pub fn narrowErrorSet(comptime E: type, err: anyerror) ?E {
    if (err == error.Unknown) return null;

    const es = @typeInfo(E).ErrorSet
        orelse [0]std.builtin.Type.Error {};

    inline for (es) |e| {
        const err2 = @field(E, e.name);
        if (err == err2) return err2;
    }

    return null;
}

const MAX_DECLS = 10_000;

pub fn structConcat(subs: anytype) StructConcat(@TypeOf(subs)) {
    const Out = StructConcat(@TypeOf(subs));

    var full: Out = undefined;
    comptime var fullIndex: comptime_int = 0;

    const fullFields = comptime std.meta.fieldNames(Out);

    inline for (0..subs.len) |i| {
        const structData = subs[i];

        const structFields = comptime std.meta.fieldNames(@TypeOf(structData));

        inline for (structFields) |structFieldName| {
            @field(full, fullFields[fullIndex]) = @field(structData, structFieldName);
            fullIndex += 1;
        }
    }

    return full;
}

pub fn StructConcat(comptime subs: type) type {
    comptime var fullFields = ([1]std.builtin.Type.StructField {undefined}) ** MAX_DECLS;
    comptime var fullIndex: comptime_int = 0;

    const subsInfo = @typeInfo(subs);
    if (subsInfo != .Struct or !subsInfo.Struct.is_tuple) {
        @compileLog(subs);
        @compileError("Expected tuple struct for struct concat");
    }
    const subsFields = subsInfo.Struct.fields;

    var tuple = false;

    if (subsFields.len > 0) {
        const firstT = subsFields[0].type;
        const firstInfo = @typeInfo(firstT);
        if (firstInfo != .Struct) {
            @compileLog(firstT);
            @compileError("Expected struct for struct concat");
        }
        tuple = firstInfo.Struct.is_tuple;

        for (subsFields) |sub| {
            const structT = sub.type;
            const structInfo = @typeInfo(structT);

            if (structInfo != .Struct) {
                @compileLog(structT);
                @compileError("Expected struct for struct concat");
            }

            const structFields = structInfo.Struct.fields;

            if (structInfo.Struct.is_tuple != tuple) {
                if (structFields.len != 0) {
                    @compileLog(firstT, tuple);
                    @compileLog(structT, structInfo.Struct.is_tuple);
                    @compileError("Expected all fields to have the same tuple-ness");
                }
            }

            for (structFields) |structField| {
                fullFields[fullIndex] = std.builtin.Type.StructField {
                    .name = if (tuple) std.fmt.comptimePrint("{}", .{fullIndex}) else structField.name,
                    .type = structField.type,
                    .default_value = structField.default_value,
                    .is_comptime = false,
                    .alignment = @alignOf(structField.type),
                };

                fullIndex += 1;
            }
        }
    }

    return @Type(std.builtin.Type { .Struct = .{
        .layout = .auto,
        .backing_integer = null,
        .fields = fullFields[0..fullIndex],
        .decls = &[0]std.builtin.Type.Declaration {},
        .is_tuple = tuple,
    } });
}
