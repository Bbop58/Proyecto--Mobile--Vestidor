import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_service.dart';

class NotificationControls extends StatelessWidget {
  const NotificationControls({super.key});
  @override Widget build(BuildContext context){
    final notifications=context.read<NotificationService>();
    return Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ValueListenableBuilder<bool>(valueListenable:notifications.realtime.connected,
        builder:(_,online,_)=>Text(online?'Actualizaciones en vivo':'Reconectando actualizaciones')),
      ListenableBuilder(listenable:notifications.push,builder:(context,_)=>Wrap(
        spacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
          OutlinedButton(onPressed:notifications.push.busy?null:()=>notifications.push.enabled?
            notifications.push.disable():notifications.push.enable(),
            child:Text(notifications.push.enabled?'Desactivar avisos':'Activar avisos del sistema')),
          Text(notifications.push.status),
        ])),
    ]));
  }
}
