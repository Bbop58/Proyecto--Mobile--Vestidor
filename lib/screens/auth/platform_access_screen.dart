import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';

class PlatformAccessScreen extends StatelessWidget {
  const PlatformAccessScreen({super.key});
  static final web=Uri.parse('https://proyecto-frontend-vestidor-ten.vercel.app/plataforma/empresas');
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Acceso de plataforma')),
    body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:520),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Continúa en la web',style:Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height:16),
        const Text('La gestión de empresas, planes y suscripciones está disponible en el panel web de FashionStore. Esta app está destinada a las cuentas comerciales. Tus pendientes anteriores se conservan.'),
        const SizedBox(height:24),
        FilledButton(onPressed:() async {
          var opened=false;
          try {opened=await launchUrl(web,mode:LaunchMode.externalApplication);} catch(_) { /* Show a retryable error below. */ }
          if(!opened&&context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No se pudo abrir el navegador. Accede a la web de FashionStore desde tu navegador.')));
        },child:const Text('Abrir panel web')),
        TextButton(onPressed:()=>context.read<AuthService>().dismissPlatformAccess(),child:const Text('Ingresar con otra cuenta')),
      ]),
    )))),
  );
}
