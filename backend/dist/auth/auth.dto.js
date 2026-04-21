"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthTokenResponse = exports.GoogleAuthDto = exports.OkResponse = exports.ResetPasswordDto = exports.ForgotPasswordResponse = exports.ForgotPasswordDto = exports.LoginDto = exports.RegisterDto = void 0;
const swagger_1 = require("@nestjs/swagger");
class RegisterDto {
}
exports.RegisterDto = RegisterDto;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], RegisterDto.prototype, "email", void 0);
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], RegisterDto.prototype, "password", void 0);
__decorate([
    (0, swagger_1.ApiPropertyOptional)(),
    __metadata("design:type", String)
], RegisterDto.prototype, "displayName", void 0);
__decorate([
    (0, swagger_1.ApiPropertyOptional)(),
    __metadata("design:type", String)
], RegisterDto.prototype, "position", void 0);
__decorate([
    (0, swagger_1.ApiPropertyOptional)(),
    __metadata("design:type", String)
], RegisterDto.prototype, "nation", void 0);
class LoginDto {
}
exports.LoginDto = LoginDto;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], LoginDto.prototype, "email", void 0);
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], LoginDto.prototype, "password", void 0);
class ForgotPasswordDto {
}
exports.ForgotPasswordDto = ForgotPasswordDto;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], ForgotPasswordDto.prototype, "email", void 0);
class ForgotPasswordResponse {
}
exports.ForgotPasswordResponse = ForgotPasswordResponse;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", Boolean)
], ForgotPasswordResponse.prototype, "ok", void 0);
class ResetPasswordDto {
}
exports.ResetPasswordDto = ResetPasswordDto;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], ResetPasswordDto.prototype, "email", void 0);
__decorate([
    (0, swagger_1.ApiProperty)({ description: 'Reset token obtained from forgot-password step' }),
    __metadata("design:type", String)
], ResetPasswordDto.prototype, "token", void 0);
__decorate([
    (0, swagger_1.ApiProperty)({ description: 'New password (min 6 chars)' }),
    __metadata("design:type", String)
], ResetPasswordDto.prototype, "newPassword", void 0);
class OkResponse {
}
exports.OkResponse = OkResponse;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", Boolean)
], OkResponse.prototype, "ok", void 0);
class GoogleAuthDto {
}
exports.GoogleAuthDto = GoogleAuthDto;
__decorate([
    (0, swagger_1.ApiPropertyOptional)({ description: 'Google ID token from client (google_sign_in)' }),
    __metadata("design:type", String)
], GoogleAuthDto.prototype, "idToken", void 0);
__decorate([
    (0, swagger_1.ApiPropertyOptional)({ description: 'Google access token from client (fallback when idToken is not available)' }),
    __metadata("design:type", String)
], GoogleAuthDto.prototype, "accessToken", void 0);
__decorate([
    (0, swagger_1.ApiPropertyOptional)({ description: 'Optional display name override for first-time users' }),
    __metadata("design:type", String)
], GoogleAuthDto.prototype, "displayName", void 0);
class AuthTokenResponse {
}
exports.AuthTokenResponse = AuthTokenResponse;
__decorate([
    (0, swagger_1.ApiProperty)(),
    __metadata("design:type", String)
], AuthTokenResponse.prototype, "accessToken", void 0);
