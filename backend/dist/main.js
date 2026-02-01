"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
require("reflect-metadata");
require("dotenv/config");
const fs = __importStar(require("node:fs"));
const path = __importStar(require("node:path"));
const core_1 = require("@nestjs/core");
const swagger_1 = require("@nestjs/swagger");
const app_module_1 = require("./app.module");
async function bootstrap() {
    const app = await core_1.NestFactory.create(app_module_1.AppModule);
    const uploadDir = process.env.UPLOAD_DIR || 'uploads';
    const uploadAbs = path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
    fs.mkdirSync(uploadAbs, { recursive: true });
    const corsOrigins = (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim());
    app.enableCors({
        origin: corsOrigins.includes('*') ? true : corsOrigins,
        credentials: false,
    });
    const swaggerEnabled = (process.env.SWAGGER_ENABLED || '1') === '1';
    if (swaggerEnabled) {
        const config = new swagger_1.DocumentBuilder()
            .setTitle('ScoutAI API')
            .setDescription('Scouting platform backend')
            .setVersion('0.1.0')
            .addBearerAuth()
            .build();
        const document = swagger_1.SwaggerModule.createDocument(app, config);
        swagger_1.SwaggerModule.setup('docs', app, document);
    }
    const port = Number(process.env.PORT || 3000);
    await app.listen(port);
}
bootstrap();
